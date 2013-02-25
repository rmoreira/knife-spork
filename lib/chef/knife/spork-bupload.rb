require 'chef/knife'
require 'chef/exceptions'
require 'chef/cookbook_loader'
require 'chef/cookbook_uploader'
require 'knife-spork/runner'
require 'socket'

module KnifeSpork
  class SporkBupload < Chef::Knife
    include KnifeSpork::Runner

    banner 'knife spork bupload [COOKBOOKS...] (options)'

    option :cookbook_path,
      :short => '-o PATH:PATH',
      :long => '--cookbook-path PATH:PATH',
      :description => 'A colon-separated path to look for cookbooks in',
      :proc => lambda { |o| o.split(':') }

    option :freeze,
      :long => '--freeze',
      :description => 'Freeze this version of the cookbook so that it cannot be overwritten',
      :boolean => true

    option :depends,
      :short => '-D',
      :long => '--include-dependencies',
      :description => 'Also upload cookbook dependencies'

    def run
      self.config = Chef::Config.merge!(config)
      config[:cookbook_path] ||= Chef::Config[:cookbook_path]
      ui.info "Config looks like : #{config}"

      if @name_args.empty?
        show_usage
        ui.error("You must specify the --all flag or at least one cookbook name")
        exit 1
      end
      
      run_plugins(:git_add)
      run_plugins(:git_commit)

      bupload(@name_args.first)

    end

    private
    def include_dependencies
      @cookbooks.each do |cookbook|
        @cookbooks.concat(load_cookbooks(cookbook.metadata.dependencies.keys))
      end

      @cookbooks.uniq!
    end

    def bupload(cookbook)
      IO.popen("bash", "w+") do |pipe|
        pipe.puts("knife spork bump #{cookbook}")
        pipe.puts("knife spork upload #{cookbook}")
        pipe.puts("knife spork promote #{cookbook}")
        pipe.close_write
        output = pipe.read
      end
      ui.msg output
    end

    # Ensures that all the cookbooks dependencies are either already on the server or being uploaded in this pass
    def check_dependencies(cookbook)
      cookbook.metadata.dependencies.each do |cookbook_name, version|
        unless server_side_cookbooks(cookbook_name, version)
          ui.error "#{cookbook.name} depends on #{cookbook_name} (#{version}), which is not currently being uploaded and cannot be found on the server!"
          exit(1)
        end
      end
    end

    def server_side_cookbooks(cookbook_name, version)
      if Chef::CookbookVersion.respond_to?(:list_all_versions)
        @server_side_cookbooks ||= Chef::CookbookVersion.list_all_versions
      else
        @server_side_cookbooks ||= Chef::CookbookVersion.list
      end

      hash = @server_side_cookbooks[cookbook_name]
      hash && hash['versions'] && hash['versions'].any?{ |v| Chef::VersionConstraint.new(version).include?(v['version']) }
    end
    
    def promote(cookbook)
      ui.msg "Trying to promote: knife spork promote #{cookbook} "
      #output = `pwd && ls -ltr`
      output = system("bash -c 'knife spork promote sporktest'")
      ui.msg "Output: #{output}"
    end
  end
end
