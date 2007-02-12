# Quoth RFC 2821:
#   SMTP transports a mail object.  A mail object contains an envelope and
#   content.
#
#   It also happens to contain a couple of ancillary other bits of
#   information these days, like what the source host was calling
#   itself, what its actual IP address was, and the actual name of that
#   IP address if the MTA is feeling particularly enthusiastic, as well
#   as an SMTP ID to aid sysadmins in sludging through logs, assuming
#   that any sysadmin still does that, and of course your own idea of
#   what your name is.
#
#   All of this ancillary information goes into the Received: header
#   which--tee hee!--this thing doesn't even bother writing!  Yet.  No
#   doubt there's an RFC probably written by one of those rabid
#   antispammers that make you feel happier just lumping it with the
#   spam (I'm sure you all know the type--"It comes from Asia!  It must
#   be spam!"  Yes, but I *AM* in Asia) saying that any email message
#   which doesn't have the required number of Received: headers in it
#   must, by definition, be spam, and is thus safe to delete on sight.
#
#   Which I suppose makes "add Received: header" part of my huge TODO
#   list, but well, you know?  I have a LIFE.  Maybe.
#
# In most pieces of software, this entire rant would be replaced by a
# complete copy of the GPL, which is I am sure a total improvement over
# the standard corporate code preamble of 18 copyright messages
# detailing every single company which has urinated on the code (and
# what year they did so in).

module Percolate

    # The SMTP::MailObject is mostly a class.  It's what is produced by the
    # Percolate::Responder class as a result of a complete SMTP transaction.
    class MailObject

        # The constructor.  It takes a whole bunch of optional
        # keyword-style parameters.  View source for more details--I
        # hope they're self- explanatory.  If they're not, I need to
        # come up with better names for them.
        def initialize(opts = {})
            @envelope_from = opts[:envelope_from]
            @envelope_to   = opts[:envelope_to]
            @content       = opts[:content]
            @origin_ip     = opts[:origin_ip]
            @heloname      = opts[:heloname]
            @myhostname    = opts[:myhostname]
            @timestamp     = Time.now
            @smtp_id       = ([nil]*16).map { rand(16).to_s(16) }.join.upcase
        end

        # You get to fiddle with these.  The SMTP standard probably has
        # some mumbling about this data being sacrosanct, but then
        # again, it also says that "content" can contain anything at all
        # and you still have to accept it (and presumably, later try to
        # reconstruct it into an actual email message).  So hey, have
        # fun!
        #
        # Also, at the time of creation, the responder doesn't know
        # necessarily who a message is meant for.  Heck, it could be
        # meant for twenty different people!
        attr_accessor :envelope_from, :envelope_to, :content

        # These four are read-only because I hate you.  They're actually
        # read-only because PRESUMABLY the guy creating an object of
        # this type (namely, the responder), knows all this information
        # at its own creation, let alone when it eventually gets around
        # to building a MailObject object.
        attr_reader :smtp_id, :heloname, :origin_ip, :myhostname
        
        begin
            require "gurgitate/mailmessage"

            # Converts a SMTP::MailObject object into a Gurgitate-Mail
            # MailMessage object.
            def to_gurgitate_mailmessage
                received = "Received: from #{@heloname} (#{@origin_ip}) " +
                           "by #{@myhostname} with SMTP ID #{smtp_id} " +
                           "for <#{@envelope_to}>; #{@timestamp.to_s}\n"
                message = @content.gsub "\r",""
                begin
                    g = Gurgitate::Mailmessage.new(received + message, 
                                                   @envelope_to, @envelope_from)
                rescue Gurgitate::IllegalHeader
                    # okay, let's MAKE a mail message (the RFC actually
                    # says that this is okay.  It says that after DATA,
                    # an SMTP server should accept pretty well any old
                    # crap.)
                    message_text = received + "From: #{@envelope_from}\n" +
                   "To: undisclosed recipients:;\n" +
                   "X-Gurgitate-Error: #{$!}\n" +
                   "\n" +
                   @content
                   return Gurgitate::Mailmessage.new(message_text, @envelope_to,
                                                     @envelope_from)
                end
            end

            # Lets you process a message with Gurgitate-Mail.  The
            # gurgitate-rules segment is given in the block.
            def gurgitate &block
                received = "Received: from #{@heloname} (#{@origin_ip}) " +
                           "by #{@myhostname} with SMTP ID #{smtp_id} " +
                           "for <#{@envelope_to}>; #{@timestamp.to_s}\n"
                message = @content.gsub "\r",""
                begin
                    Gurgitate::Gurgitate.new(message_text, @envelope_to,
                                             @envelope_from).process &block
                rescue Gurgitate::IllegalHeader
                    # okay, let's MAKE a mail message (the RFC actually
                    # says that this is okay.  It says that after DATA,
                    # an SMTP server should accept pretty well any old
                    # crap.)
                    message_text = received + "From: #{@envelope_from}\n" +
                               "To: undisclosed recipients:;\n" +
                               "X-Gurgitate-Error: #{$!}\n" +
                               "\n" +
                               @content
                    Gurgitate::Gurgitate.new(message_text, @envelope_to,
                                             @envelope_from).process &block
                end
            end

        rescue LoadError => e
            nil # and don't define to_gurgitate_mailmessage.  I'm a huge
                # egotist so I'm not including an rmail variant
                # (besides, I thought that was abandonware!  It's
                # certainly done a great job of lurching back to life,
                # encrusted with grave dirt, since Rails became popular.
        end
    end
end
