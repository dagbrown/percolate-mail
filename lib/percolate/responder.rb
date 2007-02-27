require "percolate/mail_object"

module Percolate
    # A ResponderError exception is raised when something went horribly
    # wrong for whatever reason.
    #
    # If you actually find one of these leaping into your lap in your
    # own code, and you're not trying anything gratuitously silly, I
    # want to know about it, because I have gone out of my way that
    # these errors manifest themselves in an SMTPish way as error codes.
    #
    # If you are trying something silly though, I reserve the right to
    # laugh at you.  And possibly mock you on my blog.  (Are you scared
    # now?)
    class ResponderError < Exception; end

    # This is an exception that you *should* expect to receive, if you
    # deal with the SMTP Responder yourself (you probably won't
    # though--if you're smart, you'll just use the Listener and let it
    # park itself on some port for other network services to talk to).
    # All it means is that the client has just sent a "quit" message,
    # and all is kosher, indicating that now would be a good time to
    # clean up shop.
    #
    # NOTE VERY WELL THOUGH!:  When you get one of these exceptions,
    # there is still one response left in the pipe that you have to
    # deliver to the client ("221 Pleasure doing business with you") so
    # make sure you deliver that before closing the connection.  It's
    # only polite, after all.
    class TransactionFinishedException < Exception; end

    # This is the bit that actually handles the SMTP conversation with
    # the client.  Basically, you send it commands, and it acts on them.
    # There is a small amount of Rubyish magic but that's there mainly
    # because I'm lazy.  And besides, if I weren't lazy, some guys on
    # IRC would flame me.  Haha!  I kid.  Greetz to RubyPanther by the
    # way.
    class Responder

        # Sets up the new smtp responder, with the parameter "mailhostname"
        # as the SMTP hostname (as returned in the response to the SMTP
        # HELO command.)  Note that "mailhostname" can be anything at
        # all, because I no longer believe that it's possible to
        # actually figure out your own full hostname without actually
        # literally being told it.  This is probably excessively-cynical
        # of me, but I've seen what happens when wide-eyed optimists try
        # to guess hostnames, and it just isn't pretty.
        #
        # Let's just leave it at "mailhostname is a required parameter",
        # shall we?
        #
        # Also, there are some interesting options you can give this.
        # Well, only a couple.  The first is :debug which you can set to
        # true or false, which will cause it to print the SMTP
        # conversation out.  This is, of course, mostly only useful for
        # debugging.
        #
        # The other option, :originating_ip, probably more interesting,
        # comes from the listener--the IP address of the client that
        # connected.
        def initialize(mailhostname, opts={})
            @verbose_debug = opts[:debug]
            @originating_ip = opts[:originating_ip]

            @mailhostname = mailhostname
            @current_state = nil
            @current_command = nil
            @response = connect
            @mail_object=nil
            @debug_output = []
            debug "\n\n"
        end

        # This is one of the methods you have to override in a subclass
        # in order to use this class properly (unless chuckmail really 
        # is acceptable for you, in which case excellent!  Also its
        # default behaviour is to pretend to be an open relay, which
        # should delight spammers until they figure out that all of
        # their mail is being silently and cheerfully discarded, but
        # they're spammers so they won't).
        #
        # Parameters:
        # +message_object+::      A SMTP::MessageObject object, with envelope
        #                         data and the message itself (which could, as
        #                         the RFC says, be any old crap at all!  Don't
        #                         even expect an RFC2822-formatted message)
        def process_message message_object
            return true
        end

        # Override this if you care about who the sender is (you
        # probably do care who the sender is).
        #
        # Incidentally, you probably Do Not Want To Become An Open Spam
        # Relay--you really should validate both senders and recipients,
        # and only accept mail if:
        #
        # (a) the sender is local, and the recipient is remote, or
        # (b) the sender is remote, and the recipient is local.
        #
        # The definition of "local" and "remote" are, of course, up to
        # you--if you're using this to handle mail for a hundred
        # domains, then all those hundred domains are local for you--but
        # the idea is that you _shoud_ be picky about who your mail is
        # from and to.
        #
        # This method takes one argument:
        # +address+::       The email address you're validating
        def validate_sender address
            return true
        end

        # Override this if you care about the recipient (which you
        # should).  When you get to this point, the accessor "sender"
        # will work to return the sender, so that you can deal with both
        # recipient and sender here.
        def validate_recipient address
            return true
        end

        # The current message's sender, if the MAIL FROM: command has
        # been processed yet.  If it hasn't, then it returns nil, and
        # probably isn't meaningful anyway.
        def sender
            if @mail_object
                @mail_object.envelope_from
            end
        end

        # Returns the response from the server.  When there's no response,
        # returns nil.  
        #
        # I still haven't figured out what to do when there's
        # more than one response (like in the case of an ESMTP capabilities
        # list).
        def response
            resp = @response
            @response = nil
            debug "<<< #{resp}"
            resp
        end

        # Send an SMTP command to the responder.  Use this to send a
        # line of input to the responder (including a single line of
        # DATA).
        #
        # Parameters:
        # +offered_command+::   The SMTP command (with end-of-line characters
        #                       removed)
        def command offered_command
            debug ">>> #{offered_command}"
            begin
                dispatch offered_command
            rescue ResponderError => error
                @response = error.message
            end
        end

        private

        attr_reader :current_state
        attr_reader :current_command

        CommandTable = { 
            /^helo ([a-z0-9.-]+)$/i => :helo,
            /^ehlo ([a-z0-9.-]+)$/i => :ehlo,
            /^mail (.+)$/i          => :mail,
            /^rcpt (.+)$/i          => :rcpt,
            /^data$/i               => :data,
            /^\.$/                  => :endmessage,
            /^rset$/i               => :rset,
            /^quit$/i               => :quit
        }

        StateTable = {
            :connect => { :states => [ nil ], 
                :error => "This should never happen" },
            :smtp_greeted_helo => { :states => [ :connect,
                                    :smtp_greeted_helo,
                                    :smtp_greeted_ehlo,
                                    :smtp_mail_started,
                                    :smtp_rcpt_received,
                                    :message_received ],
                                    :error => nil },
            :smtp_greeted_ehlo => { :states => [ :connect ],
                                    :error => nil },
            :smtp_mail_started => { :states => [ :smtp_greeted_helo, 
                                                 :smtp_greeted_ehlo,
                                                 :message_received ], 
                                    :error => "Can't say MAIL right now" }, 
            :smtp_rcpt_received => { :states => [ :smtp_mail_started,
                                                  :smtp_rcpt_received ],
                       :error => "need MAIL FROM: first" },
            :data => { :states => [ :smtp_rcpt_received ],
                       :error => "Specify sender and recipient first" },
            :message_received => { :states => [ :data ],
                       :error => "500 command not recognized" },
            :quit => { :states => [ :ANY ],
                       :error => nil },
        }

        def debug debug_string
            @debugging_stream ||= []
            @debugging_stream << debug_string
            if @verbose_debug
                $stderr.puts debug_string
            end
        end

        def dispatch offered_command
            if @current_state == :data
                handle_message_data offered_command
                return true
            end

            CommandTable.keys.each do |regex|
                matchdata = regex.match offered_command
                if matchdata then
                    return send(CommandTable[regex],*(matchdata.to_a[1..-1]))
                end
            end
            raise ResponderError, "500 command not recognized"
        end

        def connect
            validate_state :connect
            respond "220 Ok"
        end

        # Makes sure that the commands are all happening in the right
        # order (and complains if they're not)
        def validate_state target_state
            unless StateTable[target_state][:states].member? current_state or
                StateTable[target_state][:states] == [ :ANY ]
                raise ResponderError, "503 #{StateTable[target_state][:error]}"
            end
            @target_state = target_state
        end

        def respond response
            @current_state = @target_state
            @response = response
        end

        # The smtp commands.  This is thus far not a complete set of
        # every single imagineable SMTP command, but it's certainly
        # enough to be able to fairly call this an "SMTP server".
        #
        # If you want documentation about what each of these does, see
        # RFC2821, which explains it much better and in far greater
        # detail than I could.

        def helo remotehost
            validate_state :smtp_greeted_helo
            @heloname = remotehost
            @mail_object = nil
            @greeting_state = :smtp_greeted_helo # for rset
            respond "250 #{@mailhostname}"
        end

        def ehlo remotehost
            validate_state :smtp_greeted_ehlo
            @heloname = remotehost
            @mail_object = nil
            @greeting_state = :smtp_greeted_ehlo # for rset
            respond "250 #{@mailhostname}"
        end

        def mail sender
            validate_state :smtp_mail_started
            matchdata=sender.match(/^From:\<(.*)\>$/i);
            unless matchdata
                raise ResponderError, "501 bad MAIL FROM: parameter"
            end

            mail_from = matchdata[1]

            validated, message = validate_sender mail_from
            unless validated
                raise ResponderError, "551 #{message || 'no'}"
            end

            @mail_object = MailObject.new(:envelope_from => mail_from,
                                          :heloname => @heloname,
                                          :origin_ip => @originating_ip,
                                          :myhostname => @mailhostname)
            respond "250 #{message || 'ok'}"
        end

        def rcpt recipient
            validate_state :smtp_rcpt_received
            matchdata=recipient.match(/^To:\<(.*)\>$/i);
            unless matchdata
                raise ResponderError, "501 bad RCPT TO: parameter"
            end

            rcpt_to = matchdata[1]

            @mail_object.envelope_to ||= []

            validated, message = validate_recipient rcpt_to
            unless validated
                raise ResponderError, "551 #{message || 'no'}"
            end
            @mail_object.envelope_to << rcpt_to
            respond "250 #{message || 'ok'}"
        end

        def data
            validate_state :data
            @mail_object.content ||= ""
            respond "354 end data with <cr><lf>.<cr><lf>"
        end

        def rset
            if @mail_object
                @mail_object = nil
                @target_state = @greeting_state
            end
            respond "250 Ok"
        end

        def quit
            validate_state :quit
            if @mail_object
                @mail_object = nil
            end
            respond "221 Pleasure doing business with you"
            raise TransactionFinishedException
        end

        # The special-case code for message data, which unlike other
        # data, is delivered as lots and lots of lines with a sentinel.
        def handle_message_data message_line
            if message_line == "."
                @current_state = :message_received
                result, text = process_message @mail_object
                if result or
                    ( String === result and text.nil? )
                    if String === result and text.nil?
                        @response = "250 #{result}"
                    elsif result == true and text.nil?
                        @response = "250 accepted, SMTP id is " + 
                            @mail_object.smtp_id
                    elsif result == true and text
                        @response = "250 #{text}"
                    end
                else
                    @response = "550 #{text || 'Email rejected, sorry'}"
                end
            elsif message_line == ".."
                @mail_object.content << "." + "\r\n"
            else
                @mail_object.content << message_line + "\r\n"
            end
        end
    end
end
