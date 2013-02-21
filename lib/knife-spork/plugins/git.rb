require 'knife-spork/plugins/plugin'

module KnifeSpork
  module Plugins
    class Git < Plugin
      name :git

      def perform; end

      def before_bump
        ui.msg "Before Bump"
        git_pull(environment_path) unless cookbook_path.include?(environment_path.gsub"/environments","")
        git_pull_submodules(environment_path) unless cookbook_path.include?(environment_path.gsub"/environments","")
        cookbooks.each do |cookbook|
          git_pull(cookbook.root_dir)
          git_pull_submodules(cookbook.root_dir)
        end
        git_pre_commit
        git_push
      end

      def before_upload
        ui.msg "Before Upload"
        git_pull(environment_path) unless cookbook_path.include?(environment_path.gsub"/environments","")
        git_pull_submodules(environment_path) unless cookbook_path.include?(environment_path.gsub"/environments","")
        cookbooks.each do |cookbook|
          git_pull(cookbook.root_dir)
          git_pull_submodules(cookbook.root_dir)
        end
        git_pre_commit
        git_push
      end

      def before_promote
        ui.msg "Before Promote"
        cookbooks.each do |cookbook|
          git_pull(environment_path) unless cookbook.root_dir.include?(environment_path.gsub"/environments","")
          git_pull_submodules(environment_path) unless cookbook.root_dir.include?(environment_path.gsub"/environments","")
          git_pull(cookbook.root_dir)
          git_pull_submodules(cookbook.root_dir)
        end
      end

      def after_bump
        ui.msg "After Bump"
        cookbooks.each do |cookbook|
          git_add(cookbook.root_dir,"metadata.rb")
        end
        git_commit
        git_push
      end

      def after_promote_local
        ui.msg "After Promote Local"
        environments.each do |environment|
          git_add(environment_path,"#{environment}.json")
        end
        git_commit
        git_push
      end

      private
      def git
        safe_require 'git'
        log = Logger.new(STDOUT)
        log.level = Logger::WARN
        @git ||= begin
          ::Git.open('.', :log => log)
        rescue
          ui.error 'You are not currently in a git repository. Please ensure you are in a git repo, a repo subdirectory, or remove the git plugin from your KnifeSpork configuration!'
          exit(0)
        end
      end

      # In this case, a git pull will:
      #   - Stash local changes
      #   - Pull from the remote
      #   - Pop the stash
      def git_pull(path)
        ui.msg "Git Pull #{path}"
        if is_repo?(path)
          ui.msg "Git: Pulling latest changes from #{path}"
          output = IO.popen("git pull 2>&1")
          Process.wait
          exit_code = $?
          if !exit_code.exitstatus ==  0
            ui.error "#{output.read()}\n"
            exit 1
          end
        end
      end

      def git_pull_submodules(path)
        if is_repo?(path)
          ui.msg "Pulling latest changes from git submodules (if any)"
          top_level = `cd #{path} && git rev-parse --show-toplevel 2>&1`.chomp
          if is_submodule?(top_level)
            top_level = get_parent_dir(top_level)
          end
          output = IO.popen("cd #{top_level} && git submodule foreach git pull 2>&1")
          Process.wait
          exit_code = $?
          if !exit_code.exitstatus ==  0
              ui.error "#{output.read()}\n"
              exit 1
          end
        end
      end
      
      def git_add(filepath,filename)
        ui.msg "Git Add #{filename}"
        if is_repo?(filepath)
          ui.msg "Git add'ing #{filepath}/#{filename}"
          output = IO.popen("cd #{filepath} && git add #{filename}")
          Process.wait
          exit_code = $?
          if !exit_code.exitstatus ==  0
              ui.error "#{output.read()}\n"
              exit 1
          end
        end
      end
      
      # Commit changes, if any
      def git_commit
        begin
          ui.msg "Committing Changes"
          git.add('.')
          `git ls-files --deleted`.chomp.split("\n").each{ |f| git.remove(f) }
          git.commit_all "[KnifeSpork] Bumping cookbooks:\n#{cookbooks.collect{|c| "  #{c.name}@#{c.version}"}.join("\n")}"
        rescue ::Git::GitExecuteError; end
      end
      
      # Pre Commit changes, if any before any pull requests
      def git_pre_commit
        begin
          ui.msg "Pre Committing Changes before pull"
          git.add('.')
          `git ls-files --deleted`.chomp.split("\n").each{ |f| git.remove(f) }
          ui.msg "[PreCommit] Bumping cookbooks:\n#{cookbooks.collect{|c| "  #{c.name}@#{c.version}"}.join("\n")}"
          git.commit_all "[PreCommit] Bumping cookbooks:\n#{cookbooks.collect{|c| "  #{c.name}@#{c.version}"}.join("\n")}"
        rescue ::Git::GitExecuteError; end
      end

      def git_push(tags = false)
        begin
        ui.msg "Git Push"
          git.push remote, branch, tags
        rescue ::Git::GitExecuteError => e
          ui.error "Could not push to remote #{remote}/#{branch}. Does it exist?"
        end
      end

      def git_tag(tag)
        begin
          git.add_tag(tag)
        rescue ::Git::GitExecuteError => e
          ui.error "Could not tag #{tag_name}. Does it already exist?"
          ui.error 'You may need to delete the tag before running promote again.'
        end
      end

      def is_repo?(path)
        output = IO.popen("cd #{path} && git rev-parse --git-dir 2>&1")
        Process.wait
        if $? != 0
            ui.warn "#{path} is not a git repo, skipping..."
            return false
        else
            return true
        end
      end

      def is_submodule?(path)
        top_level = `cd #{path} && git rev-parse --show-toplevel 2>&1`.chomp
        output = IO.popen("cd #{top_level}/.. && git rev-parse --show-toplevel 2>&1")
        Process.wait
        if $? != 0
          return false
        else
          return true
        end
      end

      def get_parent_dir(path)
        top_level = path
        return_code = 0
        while return_code == 0
          output = IO.popen("cd #{top_level}/.. && git rev-parse --show-toplevel 2>&1")
          Process.wait
          return_code = $?
          if return_code == 0
            top_level = output.read.chomp
          end
        end
        top_level
      end

      def remote
        ui.msg "#{config.remote}"
        config.remote || 'origin'
      end

      def branch
        ui.msg "#{config.branch}"
        config.branch || 'master'
      end

      def tag_name
        cookbooks.collect{|c| "#{c.name}@#{c.version}"}.join('-')
      end
    end
  end
end
