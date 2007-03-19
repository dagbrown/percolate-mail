require "percolate/smtp/responder"
require "socket"

module Percolate
    class Listener
        CRLF = "\r\n"

        # The constructor for an smtp listener.  This has a number of
        # options you can give it, a lot of which already have defaults.
        #
        # :verbose_debug::   Just turns on lots of debugging output.
        # :responder::       The responder class you want to use as a
        #                    responder.  This defaults to, as you might
        #                    expect, SMTP::Responder, but really I want
        #                    you to subclass that and write your own 
        #                    mail handling code.  Its normal default
        #                    behaviour is to act as a sort of null MTA,
        #                    accepting and cheerfully discarding
        #                    messages.
        # :ipaddress::       The IP address you want this to listen on.
        #                    Defaults to 0.0.0.0 (all available
        #                    interfaces)
        # :port              The port to listen on.  I have it default
        #                    to 10025 rather than, as you might expect,
        #                    25, because 25 is a privileged port and so
        #                    you have to be root to listen on it.
        #                    Unless you're foolish enough to try
        #                    building a real MTA on this (just leave
        #                    that kind of foolishness to me), just stick
        #                    to leaving this at a high port and letting
        #                    Postfix or Sendmail or your real MTA of
        #                    choice filter through it.
        def initialize(opts = {})
            @ipaddress = "0.0.0.0"
            @hostname = "localhost"
            @port = 10025
            @responder = SMTP::Responder

            @verbose_debug = opts[:debug]
            @ipaddress     = opts[:ipaddr] if opts[:ipaddr]
            @port          = opts[:port] if opts[:port]
            @hostname      = opts[:hostname] if opts[:hostname]
            @responder     = opts[:responder] if opts[:responder]

            @socket = TCPServer.new @ipaddress, @port
        end

        # My current hostname as return by the HELO and EHLO commands
        attr_accessor :hostname

        # Once the listener is running, let it start handling mail by
        # invoking the poorly-named "go" method.
        def go
            trap 'CLD' do 
                debug "Got SIGCHLD"
                reap_children 
            end
            trap 'INT' do 
                debug "Got SIGINT"
                cleanup_and_exit 
            end
            
            @pids = []
            while mailsocket=@socket.accept
                debug "Got connection from #{mailsocket.peeraddr[3]}"
                pid = handle_connection mailsocket
                mailsocket.close
                @pids << pid
            end
        end

        private

        def handle_connection mailsocket
            fork do # I can't imagine the contortions required
                          # in Win32 to get "fork" to work, but hey,
                          # maybe someone did so anyway.
                responder = @responder.new hostname, 
                    :originating_ip => mailsocket.peeraddr[3]
                begin
                    while true
                        response = responder.response
                        handle_response mailsocket, response

                        cmd = mailsocket.readline
                        cmd.chomp! CRLF
                        responder.command cmd
                    end
                rescue TransactionFinishedException
                    mailsocket.puts responder.response + CRLF
                    mailsocket.close
                    exit!
                rescue Exception => e
                    mailsocket.print e.exception + CRLF
                    mailsocket.print "From " + e.traceback.join(CRLF + "from ") + CRLF
                    mailsocket.print "421 Server confused, shutting down" +
                        CRLF
                    mailsocket.close
                    # $stderr.puts e.exception
                    exit!
                end
            end
        end

        def handle_response mailsocket, response
            case response 
            when String then
                mailsocket.write response + CRLF
            when Array then
                response.each do |str|
                    mailsocket.write str + CRLF
                end
            when NilClass then
                nil # server has nothing to say
            end
        end

        # Prevent a BRAAAAAAINS situation
        def reap_children
            begin
                while reaped=Process.waitpid
                    @pids -= [ reaped ]
                end
            rescue Errno::ECHILD
                nil
            end
        end

        def cleanup_and_exit
            debug "Shutting down"
            @socket.close
            exit
        end

        def debug debug_string
            @debugging_stream ||= []
            @debugging_stream << debug_string
            if @verbose_debug
                $stderr.puts debug_string
            end
        end
    end
end
