require 'chef/knife'
require 'chef/exceptions'
require 'chef/cookbook_loader'
require 'chef/cookbook_uploader'
require 'knife-spork/runner'
require 'socket'

module KnifeSpork
  class SporkBupload < Chef::Knife
    include KnifeSpork::Runner

    banner 'knife spork bupload COOKBOOK (options)'

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

      if @name_args.empty?
        show_usage
        ui.error("You must specify the at least one cookbook name")
        exit 1
      end
      
      ui.msg "Adding and committing changes to git repo"
      ui.msg "-----------------------------------------"
      run_plugins(:git_add)
      run_plugins(:git_commit)

      bupload(@name_args.first)

    end

    private

    def bupload(cookbook)
      begin
        [ "bash -c 'knife spork bump #{cookbook}'",
          "bash -c 'knife spork upload #{cookbook}'",
          "bash -c 'knife spork promote #{cookbook} --remote'"
        ].each do |cmd|
            ui.msg "\n## Begin: #{cmd} ##"
            pipe = IO.popen(cmd)
            ui.info(pipe.readlines)
            pipe.close
            ui.msg "\n## End: #{cmd} ##\n"
          end
      rescue StandardError => e 
        ui.error(e.inspect)
      end
    end

  end
end
