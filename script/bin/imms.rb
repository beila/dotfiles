#! /usr/bin/ruby

# imms interface library

require 'socket'
require 'logger'
require 'thread'

class IMMS
  VERSION = "3.0.2"
  
  attr_accessor :log, :xidle

  IMMS_DIR = File.join(ENV['HOME'], ".imms")
  IMMS_LOCK = File.join(IMMS_DIR, ".immsd_lock")
  DEFAULT_SOCKET = File.join(IMMS_DIR, "socket")

  def initialize xidle = true
    @log = Logger.new $stdout
    @mutex = Mutex.new

    @agents = []

    @xidle = xidle

    @socket = nil
    connect DEFAULT_SOCKET
  end
  
  def connect sock=DEFAULT_SOCKET
    return "Already connected" if connected?
    unless File.exist? IMMS_LOCK
      @immsd = IO.popen "immsd"
      @immsd.readline
    end
    case sock
      when IO
        @socket = sock
      else
        @socket = UNIXSocket.new sock
    end

    @listen = Thread.new do
      @socket.each_line do |line|
        @log.debug "<< #{line}"
        func, *args = line.split
        func[0] = func[0,1].downcase
        send "rec_#{func}".to_sym, *args
      end
      @socket = nil
    end
    write_command "IMMS"
    setup xidle
    true
  end
  def disconnect
    @listen.terminate if Thread === @listen
    @socket.close
    @socket = nil
  end
  def connected?
    !@socket.nil?
  end

  def log file
    @log = Logger.new file
  end
  def xidle= x
    @xidle = x
    setup x if connected?
  end

  def register agent
    @agents << agent unless @agents.include? agent
    @log.debug "** Adding agent: #{agent.class}"
  end
  def unregister agent
    @agents.delete agent
    @log.debug "** Removing agent: #{agent.class}"
  end

  def updatePlaylist list
    list.each_with_index do |s,i|
      playlist i, s
    end
    playlistEnd
  end

  private

  def write_command *args
    raise IOError, "IMMS not connected" unless connected?
    line = args.join " "
    @log.debug ">> #{line}"
    @mutex.synchronize { @socket.puts line }
  end
  def notify command, *args
    command = command.to_sym
    @log.debug "** Notifying agents: #{command}"
    @agents.each do |a|
      a.send command, *args if a.respond_to? command
    end
  end

  public
  ### setup
  def setup xidle
    x = xidle ? 1 : 0
    write_command "Setup", x
  end

  ### output
  def startSong index, path
    # a song started
    write_command "StartSong", index, path
  end
  def endSong ended, jumped=false, bad=false
    # song ended, did it end norally? was something else jumped to?
    # bad is when we don't know either
    bad = true if ended.nil? and jumped.nil?
    ended ||= false
    jumped ||= false

    write_command "EndSong", *[ended, jumped, bad].map {|a| a ? 1 : 0}
  end
  def selectNext
    # request that imms choose a song for us
    write_command "SelectNext"
  end
  def playlistChanged length
    # called when the playlist has changed
    write_command "PlaylistChanged", length
  end
  def playlistItem index, path
    # in response to getPlaylistItem
    # path = "\"#{path}\"" unless path[/^".*"$/]
    write_command "PlaylistItem", index, path
  end
  def playlist index, path
    # just like playlistItem, but used when responding to getEntirePlaylist
    # path = "\"#{path}\"" unless path[/^".*"$/]
    write_command "Playlist", index, path
  end
  def playlistEnd
    # called after all playlist responses to getEntirePlaylist
    write_command "PlaylistEnd"
  end

  protected
  ### input
  def rec_resetSelection
    # remove the queued song and re-query IMMS
    notify :cancel_selection
  end
  def rec_tryAgain
    # send selectNext again
    notify :try_again
  end
  def rec_enqueueNext index
    # enqueue list[index] to play
    notify :enqueue, index
  end
  def rec_playlistChanged
    # imms thinks the playlist changed, respond with playlistChanged
    notify :send_playlist_length
  end
  def rec_getPlaylistItem index
    # return song at index
    notify :send_song, index
  end
  def rec_getEntirePlaylist
    # playlist, playlist,... playlistEnd
    # agents should respond with updatePlaylist(list)
    # list should be an array of paths
    notify :send_playlist
  end


  def method_missing func, *args
    if func.to_s[/^rec_/] # came from imms
      func = func.to_s.split(/^rec_/)[1]
      @log.info "!! Unexpected response from imms: #{func} #{args.join " "}"
    else
      super
    end
  end
end

if __FILE__ == $0
  class IMMS_CLI < IMMS
    def puts str
      write_command str
    end
  end

  cli = IMMS_CLI.new
  $stdin.each_line do |line|
    cli.puts line
  end
  cli.disconnect
end
