# -*- coding: utf-8 -*-
module Grit

  class Submodule
    # Public: The Grit::Repo instance for submodule repo
    attr_reader :repo

    # Public: The String of path of submodule (relative path inside parent repo)
    attr_reader :path

    # Public: url of submodule remote
    attr_reader :url

    # Public: The Grit::Repo instance for parent repo
    attr_reader :parent

    # Create submodules for given parent and ref
    #   +parent+ is parent repo of type Grit::Repo
    #   +ref+ is the committish (defaults to 'master')
    # Returns a Hash of { <path:String> => <submodule:Grit::Submodule> }
    # Returns {} if parent doesn't contain submodules
    def self.create_submodules(parent, ref = "master")
      rst = {}
      submodules_info = self.config(parent, ref)
      submodules_info.each do |path, atts|
        subm = Submodule.new(path, atts['url'], parent)
        rst[path] = subm
      end

      rst
    end

    # The configuration information for the given +repo+
    #   +repo+ is the Repo
    #   +ref+ is the committish (defaults to 'master')
    #
    # Returns a Hash of { <path:String> => { 'url' => <url:String>, 'id' => <id:String> } }
    # Returns {} if no .gitmodules file was found
    def self.config(repo, ref = "master")
      commit = repo.commit(ref)
      blob = commit.tree/'.gitmodules'
      return {} unless blob

      lines = blob.data.gsub(/\r\n?/, "\n" ).split("\n")

      config = {}
      current = nil

      lines.each do |line|
        if line =~ /^\[submodule "(.+)"\]$/
          current = $1
          config[current] = {}
        elsif line =~ /^\t(\w+) = (.+)$/
          config[current][$1] = $2
        else
          # ignore
        end
      end

      config
    end

    # Initializer for Grit::Submodule
    # path   - relative path within parent's working dir
    # url    - url of submodule
    # parent - Grit::Repo instance of parent repo
    def initialize(path, url, parent)
      full_path = File.join(parent.working_dir, path)
      @repo = Repo.new(full_path)
      @path = path
      @url = url
      @parent = parent
    end


    def has_file?(file)
      file.start_with?(@path)
    end

    # Pretty object inspection
    def inspect
      %Q{#<Grit::Submodule "#{@path}" -- "#{@url}">}
    end
  end # Submodule

end # Grit
