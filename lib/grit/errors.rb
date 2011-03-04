module Grit
  module Errors

    class InvalidGitRepositoryError < StandardError
    end

    class NoSuchPathError < StandardError
    end

    class InvalidObjectType < StandardError
    end

    class MergeFailed < StandardError
    end

    # TODO: rename it
    class AutoMergeFailed < MergeFailed
      attr_reader :conflicted
      alias_method :unmerged, :conflicted
      def initialize(files)
        @conflicted = files
      end
    end

    class UncommittedChanges < MergeFailed
      attr_reader :changed
      alias_method :uncommitted, :changed
      def initialize(files)
        @changed = files
      end
    end

    class PushError < StandardError
    end

    class DenyNonFastForward < PushError
    end

    class RefuseCurrentBranch < PushError
      attr_reader :branch_name
      def initialize(branch_name)
        @branch_name = branch_name
      end
    end

    class GitTimeout < RuntimeError
      attr_reader :command
      attr_reader :bytes_read

      def initialize(command = nil, bytes_read = nil)
        @command = command
        @bytes_read = bytes_read
      end
    end

    # Raised when a native git command exits with non-zero.
    class CommandFailed < StandardError
      # The full git command that failed as a String.
      attr_reader :command

      # The integer exit status.
      attr_reader :exitstatus

      # Everything output on the command's stderr as a String.
      attr_reader :err

      def initialize(command, exitstatus=nil, err='')
        if exitstatus
          @command = command
          @exitstatus = exitstatus
          @err = err
          message = "Command failed [#{exitstatus}]: #{command}"
          message << "\n\n" << err unless err.nil? || err.empty?
          super message
        else
          super command
        end
      end
    end

  end
end
