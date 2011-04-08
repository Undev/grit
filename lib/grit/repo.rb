module Grit

  class Repo
    DAEMON_EXPORT_FILE = 'git-daemon-export-ok'
    BATCH_PARSERS      = {
      'commit' => ::Grit::Commit
    }

    # Public: The String path of the Git repo.
    attr_reader :path

    # Public: The String path to the working directory of the repo, or nil if
    # there is no working directory.
    attr_reader :working_dir

    # Public: The Boolean of whether or not the repo is bare.
    attr_reader :bare

    # Public: The Grit::Git command line interface object.
    attr_reader :git

    # Public: The hash of "submodule_name" => Grit::Submodule
    attr_reader :submodules

    # Public: Create a new Repo instance.
    #
    # path    - The String path to either the root git directory or the bare
    #           git repo. Bare repos are expected to end with ".git".
    # options - A Hash of options (default: {}):
    #           :is_bare - Boolean whether to consider the repo as bare even
    #                      if the repo name does not end with ".git".
    #
    # Examples
    #
    #   r = Repo.new("/Users/tom/dev/normal")
    #   r = Repo.new("/Users/tom/public/bare.git")
    #   r = Repo.new("/Users/tom/public/bare", {:is_bare => true})
    #
    # Returns a newly initialized Grit::Repo.
    # Raises Grit::Errors::InvalidGitRepositoryError if the path
    #   exists but is not a Git repository.
    # Raises Grit::Errors::NoSuchPathError if the path does not exist.
    def initialize(path, options = {})
      git_path = File.expand_path(path)

      raise Grit::Errors::NoSuchPathError.new(git_path) unless File.exist? git_path

      @bare = options[:is_bare]

      unless @bare
        real_git_path = File.join(git_path, '.git')
        if File.exist? real_git_path
          git_path = real_git_path
        else
          @bare = true
        end
      end

      if Dir.new(git_path).count > 2
        unless File.exist?(File.join(git_path, 'HEAD')) &&
           File.stat(File.join(git_path, 'objects')).directory? &&
           File.stat(File.join(git_path, 'refs')).directory?
          raise Grit::Errors::InvalidGitRepositoryError.new(git_path)
        end
      end

      @path = git_path
      @working_dir = File.dirname(git_path) if !@bare

      @git = Git.new(@path)
      @submodules = Grit::Submodule.create_submodules(self)

    end

    # Public: Initialize a git repository (create it on the filesystem). By
    # default, the newly created repository will contain a working directory.
    # If you would like to create a bare repo, use Grit::Repo.init_bare.
    #
    # path         - The String full path to the repo. Traditionally ends with
    #                "/<name>.git".
    # git_options  - A Hash of additional options to the git init command
    #                (default: {}).
    # repo_options - A Hash of additional options to the Grit::Repo.new call
    #                (default: {}).
    #
    # Examples
    #
    #   Grit::Repo.init('/var/git/myrepo.git')
    #
    # Returns the newly created Grit::Repo.
    def self.init(path, git_options = {}, repo_options = {})
      git_options = {:base => false}.merge(git_options)
      git = Git.new(path)
      git.fs_mkdir('..')
      git.init(git_options, path)
      self.new(path, repo_options)
    end

    # Public: Initialize a bare git repository (create it on the filesystem).
    #
    # path         - The String full path to the repo. Traditionally ends with
    #                "/<name>.git".
    # git_options  - A Hash of additional options to the git init command
    #                (default: {}).
    # repo_options - A Hash of additional options to the Grit::Repo.new call
    #                (default: {}).
    #
    # Examples
    #
    #   Grit::Repo.init_bare('/var/git/myrepo.git')
    #
    # Returns the newly created Grit::Repo.
    def self.init_bare(path, git_options = {}, repo_options = {})
      git_options = {:bare => true}.merge(git_options)
      git = Git.new(path)
      git.fs_mkdir('..')
      git.init(git_options)
      repo_options = {:is_bare => true}.merge(repo_options)
      self.new(path, repo_options)
    end

    # Public: Initialize a bare Git repository (create it on the filesystem)
    # or, if the repo already exists, simply return it.
    #
    # path         - The String full path to the repo. Traditionally ends with
    #                "/<name>.git".
    # git_options  - A Hash of additional options to the git init command
    #                (default: {}).
    # repo_options - A Hash of additional options to the Grit::Repo.new call
    #                (default: {}).
    #
    # Returns the new or existing Grit::Repo.
    def self.init_bare_or_open(path, git_options = {}, repo_options = {})
      git = Git.new(path)

      unless git.exist?
        git.fs_mkdir(path)
        git.init(git_options)
      end

      self.new(path, repo_options)
    end

    # Public: Create a bare fork of this repository.
    #
    # path    - The String full path of where to create the new fork.
    #           Traditionally ends with "/<name>.git".
    # options - The Hash of additional options to the git clone command.
    #           These options will be merged on top of the default Hash:
    #           {:bare => true, :shared => true}.
    #
    # Returns the newly forked Grit::Repo.
    def fork_bare(path, options = {})
      default_options = {:bare => true, :shared => true}
      real_options = default_options.merge(options)
      Git.new(path).fs_mkdir('..')
      @git.clone(real_options, @path, path)
      Repo.new(path)
    end

    # Public: Fork a bare git repository from another repo.
    #
    # path    - The String full path of the repo from which to fork..
    #           Traditionally ends with "/<name>.git".
    # options - The Hash of additional options to the git clone command.
    #           These options will be merged on top of the default Hash:
    #           {:bare => true, :shared => true}.
    #
    # Returns the newly forked Grit::Repo.
    def fork_bare_from(path, options = {})
      default_options = {:bare => true, :shared => true}
      real_options = default_options.merge(options)
      Git.new(@path).fs_mkdir('..')
      @git.clone(real_options, path, @path)
      Repo.new(@path)
    end

    # Public: Return the full Git objects from the given SHAs.  Only Commit
    # objects are parsed for now.
    #
    # *shas - Array of String SHAs.
    #
    # Returns an Array of Grit objects (Grit::Commit).
    def batch(*shas)
      shas.flatten!
      text = git.native(:cat_file, {:batch => true, :input => (shas * "\n")})
      parse_batch(text)
    end

    # Parses `git cat-file --batch` output, returning an array of Grit objects.
    #
    # text - Raw String output.
    #
    # Returns an Array of Grit objects (Grit::Commit).
    def parse_batch(text)
      io = StringIO.new(text)
      objects = []
      while line = io.gets
        sha, type, size = line.split(" ", 3)
        parser = BATCH_PARSERS[type]
        if type == 'missing' || !parser
          objects << nil
          next
        end

        object   = io.read(size.to_i + 1)
        objects << parser.parse_batch(self, sha, size, object)
      end
      objects
    end

    # The project's description. Taken verbatim from GIT_REPO/description
    #
    # Returns String
    def description
      @git.fs_read('description').chomp
    end

    # Execute a hook
    #
    # name - The name of the hook as a String
    #
    # Returns Grit::Process or nil
    def hook(name, timeout = 10)
      file = File.join(@git.git_dir, 'hooks', name)

      if File.executable?(file)
        Grit::Process.new(file, {}, { :timeout => timeout })
      end
    end

    def blame(file, commit = nil)
      Blame.new(self, file, commit)
    end

    # An array of Head objects representing the branch heads in
    # this repo
    #
    # Returns Grit::Head[] (baked)
    def heads
      Head.find_all(self)
    end

    alias_method :branches, :heads

    def get_head(head_name)
      heads.find { |h| h.name == head_name }
    end
    alias_method :branch, :get_head

    def is_head?(head_name)
      get_head(head_name)
    end
    alias_method :has_branch?, :is_head?

    # Object reprsenting the current repo head.
    #
    # Returns Grit::Head (baked)
    def head
      Head.current(self)
    end

    def remote_branch(remote, name)
      remote_hash[remote][name]
    end

    def create_branch(name, commit='master', opts={})
      Head.create(self, name, commit, opts)
    end

    def remove_branch(branch, force=false)
      opts = force ? {:D => true} : {:d => true}
      @git.branch(opts, branch.to_s)
    end

    # Commits current index
    #
    # Returns true/false if commit worked
    def commit_index(message, opts={})
      @git.commit({:m => message}.merge(opts))
    end

    # Commits all tracked and modified files
    #
    # Returns true/false if commit worked
    def commit_all(message, opts={})
      @git.commit({:a => true, :m => message}.merge(opts))
    end

    # Commits specified files, files must be known to git
    def commit_files(message, files, opts={})
      @git.commit({:m => message}.merge(opts), *files)
    end

    # Commits specified files.
    # If files aren't tracked, adds them.
    # If files don't changed, ignore them.
    # Expand all paths to check inclusion.
    def commit_files_force(message, files, opts={})
      files = files.map { |f| File.realpath(f, @working_dir) }
      st = status()
      untracked = st.untracked.keys.map { |f| File.realpath(f, @working_dir) }
      mod_names = st.modified_names.map { |f| File.realpath(f, @working_dir) }
      modified = untracked + mod_names
      mf = files.find_all { |f| modified.include?(f) }
      uf = files.find_all { |f| untracked.include?(f) }

      add(*uf)  if not uf.empty?
      commit_files(message, mf, opts)
    end

    # Adds files to the index
    def add(*files)
      @git.add({}, *files)
    end

    # Remove files from the index
    def remove(*files)
      @git.rm({}, *files.flatten)
    end


    def blame_tree(commit, path = nil)
      commit_array = @git.blame_tree(commit, path)

      final_array = {}
      commit_array.each do |file, sha|
        final_array[file] = commit(sha)
      end
      final_array
    end

    def status
      Status.new(self)
    end


    # An array of Tag objects that are available in this repo
    #
    # Returns Grit::Tag[] (baked)
    def tags
      Tag.find_all(self)
    end

    # Finds the most recent annotated tag name that is reachable from a commit.
    #
    #   @repo.recent_tag_name('master')
    #   # => "v1.0-0-abcdef"
    #
    # committish - optional commit SHA, branch, or tag name.
    # options    - optional hash of options to pass to git.
    #              Default: {:always => true}
    #              :tags => true      # use lightweight tags too.
    #              :abbrev => Integer # number of hex digits to form the unique
    #                name.  Defaults to 7.
    #              :long => true      # always output tag + commit sha
    #              # see `git describe` docs for more options.
    #
    # Returns the String tag name, or just the commit if no tag is
    # found.  If there have been updates since the tag was made, a
    # suffix is added with the number of commits since the tag, and
    # the abbreviated object name of the most recent commit.
    # Returns nil if the committish value is not found.
    def recent_tag_name(committish = nil, options = {})
      value = git.describe({:always => true}.update(options), committish.to_s).to_s.strip
    rescue Grit::Errors::CommandFailed
      nil
    end

    # An array of Remote objects representing the remote branches in
    # this repo
    #
    # Returns Grit::Remote[] (baked)
    def remotes
      Remote.find_all(self)
    end

    # Array of remote names
    def remote_list
      @git.list_remotes
    end

    # Returns hash where Grit::Remote[] grouped by parent remote name
    def remote_hash
      rst = {}
      rst.default_proc = proc { |hash, key| hash[key] = {} }
      remotes.each do |branch|
        parent_name, branch_name =  branch.name.split('/')
        rst[parent_name][branch_name] = branch
      end

      rst
    end

    def remote_add(name, url, opts={})
      @git.remote('add', opts, name, url)
      remote_hash[name]
    end

    def remote_rm(name, opts={})
      @git.remote('rm', opts, name)
    end

    def remote_fetch(name)
      @git.fetch({}, name)
    end

    # takes an array of remote names and last pushed dates
    # fetches from all of the remotes where the local fetch
    # date is earlier than the passed date, then records the
    # last fetched date
    #
    # { 'origin' => date,
    #   'peter => date,
    # }
    def remotes_fetch_needed(remotes)
      remotes.each do |remote, date|
        # TODO: check against date
        remote_fetch(remote)
      end
    end


    # An array of Ref objects representing the refs in
    # this repo
    #
    # Returns Grit::Ref[] (baked)
    def refs
      [ Head.find_all(self), Tag.find_all(self), Remote.find_all(self) ].flatten
    end

    def commit_stats(start = 'master', max_count = 10, skip = 0)
      options = {:max_count => max_count,
                 :skip => skip}

      CommitStats.find_all(self, start, options)
    end

    # An array of Commit objects representing the history of a given ref/commit
    #   +start+ is the branch/commit name (default 'master')
    #   +max_count+ is the maximum number of commits to return (default 10, use +false+ for all)
    #   +skip+ is the number of commits to skip (default 0)
    #
    # Returns Grit::Commit[] (baked)
    def commits(start = 'master', max_count = 10, skip = 0)
      options = {:max_count => max_count,
                 :skip => skip}

      Commit.find_all(self, start, options)
    end

    # The Commits objects that are reachable via +to+ but not via +from+
    # Commits are returned in chronological order.
    #   +from+ is the branch/commit name of the younger item
    #   +to+ is the branch/commit name of the older item
    #
    # Returns Grit::Commit[] (baked)
    def commits_between(from, to)
      Commit.find_all(self, "#{from}..#{to}").reverse
    end

    # The Commits objects that are newer than the specified date.
    # Commits are returned in chronological order.
    #   +start+ is the branch/commit name (default 'master')
    #   +since+ is a string represeting a date/time
    #   +extra_options+ is a hash of extra options
    #
    # Returns Grit::Commit[] (baked)
    def commits_since(start = 'master', since = '1970-01-01', extra_options = {})
      options = {:since => since}.merge(extra_options)

      Commit.find_all(self, start, options)
    end

    # The number of commits reachable by the given branch/commit
    #   +start+ is the branch/commit name (default 'master')
    #
    # Returns Integer
    def commit_count(start = 'master')
      Commit.count(self, start)
    end

    # The Commit object for the specified id
    #   +id+ is the SHA1 identifier of the commit
    #
    # Returns Grit::Commit (baked)
    def commit(id)
      options = {:max_count => 1}

      Commit.find_all(self, id, options).first
    end

    # Returns a list of commits that is in +other_repo+ but not in self
    #
    # Returns Grit::Commit[]
    def commit_deltas_from(other_repo, ref = "master", other_ref = "master")
      # TODO: we should be able to figure out the branch point, rather than
      # rev-list'ing the whole thing
      repo_refs       = @git.rev_list({}, ref).strip.split("\n")
      other_repo_refs = other_repo.git.rev_list({}, other_ref).strip.split("\n")

      (other_repo_refs - repo_refs).map do |rf|
        Commit.find_all(other_repo, rf, {:max_count => 1}).first
      end
    end

    def objects(refs)
      refs = refs.split(/\s+/) if refs.respond_to?(:to_str)
      @git.rev_list({:objects => true, :timeout => false}, *refs).
        split("\n").map { |a| a[0, 40] }
    end

    def commit_objects(refs)
      refs = refs.split(/\s+/) if refs.respond_to?(:to_str)
      @git.rev_list({:timeout => false}, *refs).split("\n").map { |a| a[0, 40] }
    end

    def objects_between(ref1, ref2 = nil)
      if ref2
        refs = "#{ref2}..#{ref1}"
      else
        refs = ref1
      end
      objects(refs)
    end

    def diff_objects(commit_sha, parents = true)
      revs = []
      Grit.no_quote = true
      if parents
        # PARENTS:
        revs = @git.diff_tree({:timeout => false, :r => true, :t => true, :m => true}, commit_sha).
          strip.split("\n").map{ |a| r = a.split(' '); r[3] if r[1] != '160000' }
      else
        # NO PARENTS:
        revs = @git.native(:ls_tree, {:timeout => false, :r => true, :t => true}, commit_sha).
          split("\n").map{ |a| a.split("\t").first.split(' ')[2] }
      end
      revs << commit(commit_sha).tree.id
      Grit.no_quote = false
      return revs.uniq.compact
    end

    # The Tree object for the given treeish reference
    #   +treeish+ is the reference (default 'master')
    #   +paths+ is an optional Array of directory paths to restrict the tree (deafult [])
    #
    # Examples
    #   repo.tree('master', ['lib/'])
    #
    # Returns Grit::Tree (baked)
    def tree(treeish = 'master', paths = [])
      Tree.construct(self, treeish, paths)
    end

    # The Blob object for the given id
    #   +id+ is the SHA1 id of the blob
    #
    # Returns Grit::Blob (unbaked)
    def blob(id)
      Blob.create(self, :id => id)
    end

    # The commit log for a treeish
    #
    # Returns Grit::Commit[]
    def log(commit = 'master', path = nil, options = {})
      commit_list = []
      default_options = {:pretty => "raw"}
      actual_options  = default_options.merge(options)
      arg = path ? [commit, '--', path] : [commit]
      begin
        commits = @git.log(actual_options, *arg)
        commit_list = Commit.list_from_string(self, commits)
      rescue Grit::Errors::CommandFailed
        # prevent fail if repo is empty
        raise if !branches.empty?
      end
      commit_list
    end

    # The diff from commit +a+ to commit +b+, optionally restricted to the given file(s)
    #   +a+ is the base commit
    #   +b+ is the other commit
    #   +paths+ is an optional list of file paths on which to restrict the diff
    def diff(a, b, *paths)
      diff = @git.native('diff', {}, a, b, '--', *paths)

      if diff =~ /diff --git a/
        diff = diff.sub(/.*?(diff --git a)/m, '\1')
      else
        diff = ''
      end
      Diff.list_from_string(self, diff)
    end

    # The commit diff for the given commit
    #   +commit+ is the commit name/id
    #
    # Returns Grit::Diff[]
    def commit_diff(commit)
      Commit.diff(self, commit)
    end

    # Archive the given treeish
    #   +treeish+ is the treeish name/id (default 'master')
    #   +prefix+ is the optional prefix
    #
    # Examples
    #   repo.archive_tar
    #   # => <String containing tar archive>
    #
    #   repo.archive_tar('a87ff14')
    #   # => <String containing tar archive for commit a87ff14>
    #
    #   repo.archive_tar('master', 'myproject/')
    #   # => <String containing tar archive and prefixed with 'myproject/'>
    #
    # Returns String (containing tar archive)
    def archive_tar(treeish = 'master', prefix = nil)
      options = {}
      options[:prefix] = prefix if prefix
      @git.archive(options, treeish)
    end

    # Archive and gzip the given treeish
    #   +treeish+ is the treeish name/id (default 'master')
    #   +prefix+ is the optional prefix
    #
    # Examples
    #   repo.archive_tar_gz
    #   # => <String containing tar.gz archive>
    #
    #   repo.archive_tar_gz('a87ff14')
    #   # => <String containing tar.gz archive for commit a87ff14>
    #
    #   repo.archive_tar_gz('master', 'myproject/')
    #   # => <String containing tar.gz archive and prefixed with 'myproject/'>
    #
    # Returns String (containing tar.gz archive)
    def archive_tar_gz(treeish = 'master', prefix = nil)
      options = {}
      options[:prefix] = prefix if prefix
      @git.archive(options, treeish, "| gzip -n")
    end

    # Write an archive directly to a file
    #   +treeish+ is the treeish name/id (default 'master')
    #   +prefix+ is the optional prefix (default nil)
    #   +filename+ is the name of the file (default 'archive.tar.gz')
    #   +format+ is the optional format (default nil)
    #   +pipe+ is the command to run the output through (default 'gzip')
    #
    # Returns nothing
    def archive_to_file(treeish = 'master', prefix = nil, filename = 'archive.tar.gz', format = nil, pipe = "gzip")
      options = {}
      options[:prefix] = prefix if prefix
      options[:format] = format if format
      @git.archive(options, treeish, "| #{pipe} > #{filename}")
    end

    # Enable git-daemon serving of this repository by writing the
    # git-daemon-export-ok file to its git directory
    #
    # Returns nothing
    def enable_daemon_serve
      @git.fs_write(DAEMON_EXPORT_FILE, '')
    end

    # Disable git-daemon serving of this repository by ensuring there is no
    # git-daemon-export-ok file in its git directory
    #
    # Returns nothing
    def disable_daemon_serve
      @git.fs_delete(DAEMON_EXPORT_FILE)
    end

    def gc_auto
      @git.gc({:auto => true})
    end

    # The list of alternates for this repo
    #
    # Returns Array[String] (pathnames of alternates)
    def alternates
      alternates_path = "objects/info/alternates"
      @git.fs_read(alternates_path).strip.split("\n")
    rescue Errno::ENOENT
      []
    end

    # Sets the alternates
    #   +alts+ is the Array of String paths representing the alternates
    #
    # Returns nothing
    def alternates=(alts)
      alts.each do |alt|
        unless File.exist?(alt)
          raise "Could not set alternates. Alternate path #{alt} must exist"
        end
      end

      if alts.empty?
        @git.fs_write('objects/info/alternates', '')
      else
        @git.fs_write('objects/info/alternates', alts.join("\n"))
      end
    end

    def config
      @config ||= Config.new(self)
    end

    def index
      Index.new(self)
    end

    def update_ref(head, commit_sha)
      return nil if !commit_sha || (commit_sha.size != 40)
      @git.fs_write("refs/heads/#{head}", commit_sha)
      commit_sha
    end

    # Rename the current repository directory.
    #   +name+ is the new name
    #
    # Returns nothing
    def rename(name)
      if @bare
        @git.fs_move('/', "../#{name}")
      else
        @git.fs_move('/', "../../#{name}")
      end
    end

    def checkout(committish, opts={})
      checkout_paths(committish, [], opts)
    end

    def checkout_paths(committish, paths, opts={})
      @git.checkout(opts, committish, *paths)
    end

    # Performs fetch.
    # By default fetching changes from `origin master`.
    def fetch(repo='origin', ref='master', opts={})
      @git.fetch(opts, repo, ref)
      # TODO: universal return-value
    end

    # Performs merge with given branch
    # Raises Grit::Errors::UncommittedChanges if there are exist
    # changed, but not committed files.
    # Raises Grit::Errors::AutoMergeFailed if merge failed due to conflicts.
    def merge(committish='master', opts={})
      changed = status().changed
      if changed.empty?
        begin
          @git.merge(opts, committish)
        rescue Grit::Errors::CommandFailed
          conflicted = status().conflicted
          if conflicted.empty?
            raise
          else
            raise Grit::Errors::AutoMergeFailed.new(conflicted_files(committish)
                                                    )
          end
        end
      else
        raise Grit::Errors::UncommittedChanges.new(changed)
      end
    end

    def abort_merge
      @git.merge({:abort => true})
    end

    # Perform fetch and then merge
    def pull(repo='origin', ref='master', fopts={}, mopts={})
      fst = fetch(repo, ref, fopts)
      mst = merge('FETCH_HEAD', mopts)

      fst + mst
    end

    def push(repo='origin', source_ref='master', target_ref='master', opts={})
      @git.push(opts, repo, "#{source_ref}:#{target_ref}")
    rescue Grit::Errors::CommandFailed => err
      # ugly, but is there right way?
      raise  if err.exitstatus != 1
      curr_branch = "refusing to update checked out branch: "
      if err.include?("non-fast-forward updates were rejected")
        raise DenyNonFastForward.new
      elsif err.include?(curr_branch)
        line = err.split("\n").find { |l| l.include?(curr_branch) }
        (_, ref) = line.split(curr_branch)
        (_, _, branch_name) = ref.split("/")
        raise RefuseCurrentBranch.new(branch_name)
      end
    end

    # Finds conflicted file by *path* in and
    # creates ConflictedFile object
    def conflicted_files(other_branch='theirs')
      conflicted = {}
      status.conflicted.each_pair do |p, f|
        conflicted[p] = ConflictedFile.create_from_file(f, other_branch)
      end

      conflicted
    end

    def submodule_add(url, path='')
      subm = Submodule.add(self, url, path)
      @submodules[subm.path] = subm

      subm
    end

    def submodules_update(opts={})
      @submodules.values.each do |subm|
        subm.update(opts)
      end
    end

    def submodules_update_recursive(opts={})
      submodules_traverse_depth_left do |bopts|
        bopts[:submodule].update(opts)
      end
    end

    def submodules_init
      @submodules.values.each do |subm|
        subm.init()
      end
    end

    def submodules_init_recursive
      submodules_traverse_depth_left do |opts|
        opts[:submodule].init()
      end
    end

    # Same as git submodule status --recursive
    # Returns Array of Hashes
    # {<path:String> => <extended result of Submodule.status>}, where
    # submodule status extended with :subm => Submodule instance
    def submodules_status
      res = {}
      submodules_traverse_depth_left do |opts|
        submodule = opts[:submodule]
        res[opts[:path_name]] = submodule.status.merge(:submodule => submodule)
      end

      res
    end

    # Commits changed submodules.
    # If names given, commits only them, otherwise, commits all submodules.
    # If .gitmodules modified in some ways (changed, or added), commits it, too
    def submodules_commit_changed(message, names=[], opts={})
      submodules_traverse_depth_right(:apply_to_parent => true) do |bopts|
        repo = bopts[:repo]
        path_name = bopts[:path_name]
        if names.empty?
          to_commit = repo.submodules.keys
        else
          to_commit = repo.submodules.keys.find_all { |n|
            name = path_name ? File.join(path_name, n) : n
            names.include?(name)
          }
        end
        if repo.status.modified_names.include?('.gitmodules')
          to_commit << '.gitmodules'
        end
        next  if to_commit.empty? || repo.status.modified_names.empty?
        repo.commit_files(message, to_commit, opts)
      end
      # cannot use commit_files_force here, because submodule path
      # couldn't be untracked
    end

    SKIP_BRANCH = Object.new

    # traverse submodules tree depth-first and executes block
    # starting from deepest submodule
    def submodules_traverse_depth_right(opts={}, &blk)
      raise LocalJumpError.new('no block given')  if blk.nil?
      apply_to_parent = opts.delete(:apply_to_parent)
      path_name = opts[:path_name]
      submodules.each_pair do |sub_name, submodule|
        pname = path_name ? File.join(path_name, sub_name) : sub_name
        submodule.repo.submodules_traverse_depth_right(:submodule => submodule,
                                                       :name => sub_name,
                                                       :path_name => pname,
                                                       &blk)
      end
      # TODO: check for submodule, not for path_name?
      blk.call(opts.merge({:repo => self}))  if path_name || apply_to_parent

      nil
    end

    # traverse submodules tree depth-first and execustes block
    # on every submodule at once
    def submodules_traverse_depth_left(opts={}, &blk)
      raise LocalJumpError.new('no block given')  if blk.nil?
      path_name = opts[:path_name]
      apply_to_parent = opts.delete(:apply_to_parent)
      r = blk.call(opts.merge({:repo => self})) if path_name || apply_to_parent
      return nil  if r.equal?(SKIP_BRANCH)
      submodules.each_pair do |sub_name, submodule|
        pname = path_name ? File.join(path_name, sub_name) : sub_name
        submodule.repo.submodules_traverse_depth_left(:submodule => submodule,
                                                      :name => sub_name,
                                                      :path_name => pname,
                                                      &blk)
      end

      nil
    end

    def make_executable(filename)
      oldmode = (File.stat filename).mode
      File.chmod((oldmode | 0755), filename)
    end

    def check_hook(hook_name, allow_rewrite=false)
      # TODO: rename func and args
      # TODO: check for proper name?
      hook_file = File.join(@git.git_dir, 'hooks', hook_name)
      if File.exist?(hook_file) && File.executable?(hook_file) && !allow_rewrite
        nil
      else
        hook_file
      end
    end

    def set_hook_from_file(hook_name, filename, force=false)
      hook_file = check_hook(hook_name, force)
      return nil  if hook_file.nil?
      if File.exists?(filename)
        FileUtils.cp(filename, hook_file)
        make_executable(hook_file)
      else
        raise NoSuchPathError.new(filename)
      end
    end

    def set_hook(hook_name, content, force=false)
      hook_file = check_hook(hook_name, force)
      return nil  if hook_file.nil?
      File.open(name, 'w') { |f| f.write contents }
    end

    # Pretty object inspection
    def inspect
      %Q{#<Grit::Repo "#{@path}">}
    end
    def to_s
      inspect
    end
  end # Repo

end # Grit
