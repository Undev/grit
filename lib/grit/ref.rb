module Grit

  class Ref
    # Find all Refs
    #   +repo+ is the Repo
    #   +options+ is a Hash of options
    #
    # Returns Grit::Ref[] (baked)
    def self.find_all(repo, options = {})
      refs = repo.git.refs(options, prefix)
      refs.split("\n").map do |ref|
        name, id = *ref.split(' ')
        self.new(name, id, repo)
      end
    end

    attr_reader :name
    attr_reader :commit

    # Instantiate a new Head
    #   +name+ is the name of the head
    #   +commit+ is the Commit that the head points to
    #
    # Returns Grit::Head (baked)
    def initialize(name, commit, parent)
      @name = name
      @commit = Commit.create(parent, :id => commit)
      @parent = parent
    end

    # Pretty object inspection
    def inspect
      %Q{#<#{self.class.name} "#{@name}">}
    end

    def to_s
      @name
    end

    protected
    def self.prefix
      "refs/#{name.to_s.gsub(/^.*::/, '').downcase}s"
    end
  end # Ref

  # A Head is a named reference to a Commit. Every Head instance contains a name
  # and a Commit object.
  #
  #   r = Grit::Repo.new("/path/to/repo")
  #   h = r.heads.first
  #   h.name       # => "master"
  #   h.commit     # => #<Grit::Commit "1c09f116cbc2cb4100fb6935bb162daa4723f455">
  #   h.commit.id  # => "1c09f116cbc2cb4100fb6935bb162daa4723f455"
  class Head < Ref

    # Get the HEAD revision of the repo.
    #   +repo+ is the Repo
    #   +options+ is a Hash of options
    #
    # Returns Grit::Head (baked)
    def self.current(repo, options = {})
      begin
        head_ref = repo.git.symbolic_ref({:q => true}, 'HEAD').chomp
      rescue Git::Errors::CommandFailed => err
        raise  if err.exitstatus != 1
        return nil
      end
      id = repo.git.rev_parse(options, head_ref)
      (_, _, branch_name) = head_ref.split('/')
      self.new(branch_name, id, repo)
    end

    # Create new branch, pointing to commit +commit+ and
    # returns Grit::Head (baked)
    def self.create(repo, name, commit='master', opts={})
      commit_id = repo.git.branch(opts, name, commit)
      self.new(name, commit_id, repo)
    end

    def change_ref(new_ref)
      new_commit_id = @parent.git.branch({:force => true}, @name, new_ref)
      @commit = Commit.create(@parent, :id => new_commit_id)

      true
    end

    def tree(*paths)
      @parent.tree(self, *paths)
    end

  end # Head

  class Remote < Ref
    def fetch
      rm_name, head_name = *@name.split('/')
      @parent.git.fetch({}, rm_name, head_name, "#{head_name}:#{@name}")
    end
  end

  class Note < Ref; end
end # Grit
