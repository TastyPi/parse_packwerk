# typed: strict

require 'sorbet-runtime'
require 'yaml'
require 'pathname'
require 'parse_packwerk/constants'
require 'parse_packwerk/violation'
require 'parse_packwerk/package_todo'
require 'parse_packwerk/package'
require 'parse_packwerk/configuration'
require 'parse_packwerk/package_set'

module ParsePackwerk
  class MissingConfiguration < StandardError
    extend T::Sig

    sig { params(packwerk_file_name: Pathname).void }
    def initialize(packwerk_file_name)
      super("We could not find a configuration file at #{packwerk_file_name}")
    end
  end

  extend T::Sig

  sig do
    returns(T::Array[Package])
  end
  def self.all
    packages_by_name.values
  end

  sig { params(name: String).returns(T.nilable(Package)) }
  def self.find(name)
    packages_by_name[name]
  end

  sig { returns(ParsePackwerk::Configuration) }
  def self.yml
    Configuration.fetch
  end

  sig { params(file_path: T.any(Pathname, String)).returns(Package) }
  def self.package_from_path(file_path)
    path_string = file_path.to_s
    @package_from_path = T.let(@package_from_path, T.nilable(T::Hash[String, Package]))
    @package_from_path ||= {}
    @package_from_path[path_string] ||= T.must(begin
      matching_package = all.find { |package| path_string.start_with?("#{package.name}/") || path_string == package.name }
      matching_package || find(ROOT_PACKAGE_NAME)
    end)
  end

  sig { params(package: ParsePackwerk::Package).void }
  def self.write_package_yml!(package)
    FileUtils.mkdir_p(package.directory)
    
    File.open(package.yml, 'w') do |file|
      merged_config = package.config

      merged_config.merge!(
        'enforce_dependencies' => package.enforce_dependencies,
        'enforce_privacy' => package.enforce_privacy
      )

      # We want checkers of the form `enforce_xyz` to be at the top
      merged_config_arr = merged_config.sort_by do |k, v|
        if k.include?('enforce')
          0
        else
          1
        end
      end

      merged_config = merged_config_arr.to_h

      unless package.public_path == DEFAULT_PUBLIC_PATH
        merged_config.merge!('public_path' => package.public_path)
      end

      if package.dependencies.any?
        merged_config.merge!('dependencies' => package.dependencies)
      end

      if package.metadata.any?
        merged_config.merge!('metadata' => package.metadata)
      end
      raw_yaml = YAML.dump(merged_config)
      # Add indentation for dependencies
      raw_yaml.gsub!(/^- /,"  - ")
      stylized_yaml = raw_yaml.gsub("---\n", '')
      file.write(stylized_yaml)
    end
  end

  # We memoize packages_by_name for fast lookup.
  # Since Graph is an immutable value object, we can create indexes and general caching mechanisms safely.
  sig { returns(T::Hash[String, Package]) }
  def self.packages_by_name
    @packages_by_name = T.let(@packages_by_name, T.nilable(T::Hash[String, Package]))
    @packages_by_name ||= begin
      all_packages = PackageSet.from(package_pathspec: yml.package_paths, exclude_pathspec: yml.exclude)
      # We want to match more specific paths first
      # Packwerk does this too and is necessary for package_from_path to work correctly.
      sorted_packages = all_packages.sort_by { |package| -package.name.length }
      sorted_packages.map{|p| [p.name, p]}.to_h
    end
  end

  sig { void }
  def self.bust_cache!
    @packages_by_name = nil
    @package_from_path = nil
  end

  private_class_method :packages_by_name
end
