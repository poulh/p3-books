require 'cinch'
require 'stringio'
require 'zip'
require 'highline'
require 'shellwords'

INFO = '::INFO::'
EBOOKS = '#ebooks'

def search( cli, bot )
    title = cli.ask "What books would you like to search for? ( Q to quit )"
    if title.downcase == 'q'
        bot.quit
        sleep( 1 )
        exit
    end
    Channel( EBOOKS ).send( "@search #{title} epub rar" )
end

def main
    cli = HighLine.new

    nick = cli.ask "What is your nickname?"

    bot = Cinch::Bot.new do
        configure do |c|
            c.server = "irc.irchighway.net"
            c.channels = [ EBOOKS ]
            c.nick = "#{nick}_p3books"
        end

        on :connect do | m |
        end

        on :join do | m |
            if( m.user == bot.nick )
                sleep(1)
                search( cli, bot )
            end
        end

        on :dcc_send do | m, dcc |
            if( m.user == 'Search' )
                f = File::open( dcc.filename, 'w' )
                dcc.accept( f )
                f.close
                z = Zip::File::open( dcc.filename )
                z.entries.each do | entry |
                    books = {}
                    results = z.read( entry.name ).split(/[\r\n]+/)
                    results.each do | result |
                        next unless result.match(/^!.*/)
                        next unless result.match(/#{INFO}/)
                        result = result[ 0, result.index( INFO ) ].strip
                        owner, title = result.split( ' ', 2 )
                        books[ title ] = owner unless books.has_key?( title )
                    end

                    cli.choose do | book_menu |
                        book_menu.prompt = "Which book would you like to download?"
                        book_menu.choice( "Search Again" ) do
                            search( cli, bot )
                        end
                        books.keys.sort.each do | title |
                            choice = [ books[ title ], title].join(' ')
                            book_menu.choice( choice ) do
                                Channel( EBOOKS ).send( choice )
                            end
                        end
                    end
                end
                File::delete( dcc.filename )
            else
                f = File::open( dcc.filename, 'w' )
                dcc.accept( f )
                f.close
                cmd = "xdg-open #{Shellwords::escape( dcc.filename )}"
                ok = system( cmd )
                search( cli, bot )

            end
        end

        on :private do | m, dcc |
            if( m.user == "Search" )
            else
                puts "#{m.user} - #{Sanitize(m.message)}"
            end
        end

        on :message do | m |
        end

    end

    bot.loggers.level = :warn
    bot.start
end

main
