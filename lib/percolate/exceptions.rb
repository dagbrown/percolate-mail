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
end
