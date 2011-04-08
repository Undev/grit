module Grit

  class Tree < BaseTreeEntry
    extend Lazy

    lazy_reader :contents

    # Construct the contents of the tree
    #   +repo+ is the Repo
    #   +treeish+ is the reference
    #   +paths+ is an optional Array of directory paths to restrict the tree
    #
    # Returns Grit::Tree (baked)
    def self.construct(repo, treeish, paths = [])
      output = repo.git.ls_tree({}, treeish.to_s, *paths)
      self.allocate.construct_initialize(repo, treeish, output)
    end

    def construct_initialize(repo, id, text)
      @repo = repo
      @id = id
      @contents = []

      text.split("\n").each do |line|
        @contents << content_from_string(repo, line)
      end
      @contents.compact!

      self
    end

    def lazy_source
      Tree.construct(@repo, @id, [])
    end

    # Parse a content item and create the appropriate object
    #   +repo+ is the Repo
    #   +text+ is the single line containing the items data in `git ls-tree` format
    #
    # Returns subclasses of Grit::BaseTreeEntry
    def content_from_string(repo, text)
      mode, type, id, name = text.split(" ", 4)
      case type
        when "tree"
          Tree.create(repo, :id => id, :mode => mode, :name => name)
        when "blob"
          Blob.create(repo, :id => id, :mode => mode, :name => name)
        when "link"
          Blob.create(repo, :id => id, :mode => mode, :name => name)
        # cases below not supported yet
        when "commit"
          BaseTreeEntry.create(repo, :id => id, :mode => mode, :name => name)
        when "tag"
          BaseTreeEntry.create(repo, :id => id, :mode => mode, :name => name)
        else
          raise Grit::Errors::InvalidObjectType, type
      end
    end

    # Find the named object in this tree's contents
    #
    # Examples
    #   Repo.new('/path/to/grit').tree/'lib'
    #   # => #<Grit::Tree "6cc23ee138be09ff8c28b07162720018b244e95e">
    #   Repo.new('/path/to/grit').tree/'README.txt'
    #   # => #<Grit::Blob "8b1e02c0fb554eed2ce2ef737a68bb369d7527df">
    #
    # Returns Grit::Blob or Grit::Tree or nil if not found
    def /(file)
      if file =~ /\//
        file.split("/").inject(self) { |acc, x| acc/x } rescue nil
      else
        self.contents.find { |c| c.name == file }
      end
    end

    # Find only Tree objects from contents
    def trees
      contents.find_all { |v| v.kind_of? Tree }
    end

    # Find only Blob objects from contents
    def blobs
      contents.find_all { |v| v.kind_of? Blob }
    end

    def walk_left(path_name=nil, &blk)
      raise LocalJumpError.new('no block given')  if blk.nil?
      trees = trees()
      name = @name
      path_name = path_name ? File.join(path_name, name) : name
      r = blk.call(name, path_name, trees, blobs())
      return nil  if r.equal?(Repo::SKIP_BRANCH)
      trees.each { |t| t.walk_left(path_name, &blk) }

      nil
    end

    def walk_right(path_name=nil, &blk)
      raise LocalJumpError.new('no block given')  if blk.nil?
      trees = tree.trees()
      name = @name
      path_name = path_name ? File.join(path_name, name) : name
      trees.each { |t| t.walk_right(path_name, &blk) }
      r = blk.call(name, path_name, trees, blobs())

      nil
    end

    # Commits tree and returns Grit::Commit object with returned id
    def commit_tree(parent = nil)
      id = @repo.git.native(:commit_tree, {:p => parent}, @id).chomp
      Commit.create(@repo, :id => id)
    end

  end # Tree

end # Grit
