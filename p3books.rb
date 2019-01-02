#!/usr/bin/ruby

require 'cinch'
require 'cinch/helpers'
require 'zip'
require 'highline'
require 'shellwords'
require 'tempfile'
require 'fileutils'

INFO = '::INFO::'.freeze
EBOOKS = '#ebooks'.freeze


# class for choosing menus
class Chooser 
    

    def initialize()
        @block = nil

        @cli = HighLine.new
        
        @search_bots = []
        @search_bot = "searchook"
        @search_suffix = "epub rar"
        set_download_path('~/Downloads/ebooks')
        
        @searches = {}
        @results = {}

        @downloaders = {}
        @preferred_downloader = nil
    end

    def do_yield(cmd)
        @block.call(cmd) if @block
    end

    def quit()
        do_yield("quit")
    end


    def choose(&block)
        @block = block
        main_menu()
    end

    def main_menu
        @cli.choose do | main_menu |
            main_menu.prompt = "What do you want to do?"

            main_menu.choice("Search For Books") do
                search()                
            end

            main_menu.choice("Choose Default Search Bot (#{@search_bot})") do
                choose_search_bot()
            end

            main_menu.choice("Change Search Suffix (#{@search_suffix})") do
                new_suffix = @cli.ask("What would you like the search suffix to be?")
                @search_suffix = new_suffix
            end 

            main_menu.choice("Change Download Path (#{@download_path})") do
                new_path = @cli.ask("What would you like the download path to be?") { |q| q.default = "" }
                set_download_path(new_path) unless new_path.empty?
            end 


            main_menu.choice("Active Searches (#{@searches.keys.size})") do
                count = 0
                @searches.each do | search, accepted |
                    
                    count += 1
                    state = accepted ? 'x' : '?'
                    puts "#{search[:bot]} #{state} - #{search[:phrase]}"
                
                end
                puts "No active searches" if count == 0
            end

            main_menu.choice("Search Results (#{@results.keys.size})") do
               choose_results()
            end

            main_menu.choice("Refresh") do
                
            end

            main_menu.choice("Quit") do
                quit()
            end 
        end
        
    end
    
    def set_download_path(path)
        @download_path = File.expand_path(path)
    end

    def set_search_bots(bots)
        @search_bots = bots
        if(@search_bot) and @search_bots.include?(@search_bot)
            # do nothing
        else
            @search_bot = @search_bots.first
        end
    end

    def main_menu_choice(menu)
        menu.choice("Main Menu") do
            main_menu()
        end
    end

    def choose_books(search, preferred_downloader)
        return unless @results.has_key?(search)
        books = @results[search]
        @cli.choose do | book_menu |
            book_menu.prompt = "Which book would you like to download?"

            main_menu_choice(book_menu)

            unless preferred_downloader
                book_menu.choice("See results from all downloaders") do
                    choose_books(search, nil)
                end
            end

            books.keys.sort.each do | title |
                downloaders = books[ title ]
                downloaders.each do | downloader |
                    if( downloader == preferred_downloader ) or ( preferred_downloader == nil ) 
                        choice = [ downloader, title].join(' ')
                        book_menu.choice( choice ) do
                            the_choice = [ downloader, title].join(' ')
                            if(downloader != @preferred_downloader)
                                answer = @cli.ask("Make #{downloader} your preferred downloader? (y/n)")
                                @preferred_downloader = downloader if answer.downcase[0] == 'y'
                            end
                            do_yield( the_choice )
                        end
                    end
                end
            end
        end
    end

    def choose_results()
        @cli.choose do | results_menu |
            results_menu.prompt = "Which Search Would you like to view?" 

            main_menu_choice(results_menu)

            @results.each do | search, results |
                results_menu.choice( "#{search[:phrase]} (#{results.keys.size})") do
                    choose_books(search, @preferred_downloader)
                end
            end
            results_menu.choice("Main Menu") do
                main_menu()
            end
        end
    end

    def choose_search_bot()
        puts "-----------here-----------"
        @cli.choose do | bot_menu |
            bot_menu.prompt = "Which search bot would you like to use?"
            main_menu_choice(bot_menu)
            @search_bots.each do |bot|
                bot_menu.choice( bot + (bot == @search_bot ? '*' : '')) do
                    @search_bot = bot
                end
            end 
        end
    end

    def add_results( search, results )
        @searches.delete(search)
        @results[search] = results
        results.each do | title, downloaders |
            downloaders.each do | downloader |
                @downloaders[ downloader ] = true
            end
        end
    end

    def request_download()

    end

    def parse_private_msg(user,msg)
        # puts "parsing #{user} - #{msg}"
        
        no_results = msg.index('Sorry')
        matches = @searches.keys.select{|search| search[:bot] == user and msg.index(search[:phrase])}
        if( no_results)
            matches.each do | match |
                add_results(match,{})
                puts "No Results: #{match[:phrase]}"
            end
        else   
            matches.each do | match |
                accepted = @searches[match]
                unless accepted
                    @searches[match] = true
                    puts "Accepted: #{match[:phrase]}"
                end
            end
        end
    end
        
    def search()
        title = @cli.ask('What books would you like to search for? ( type M to return to Main Menu )')
        case title.downcase
        when 'm'
            main_menu()
        else
            search_phrase = "#{title} #{@search_suffix}"
            search = { 
                :phrase => search_phrase,
                :bot => @search_bot,
                :cmd => "@#{@search_bot} #{search_phrase}"
            }
            puts "Search Cmd: #{search[:cmd]}"
            @searches[search] = false
            do_yield(search[:cmd])

        end
    end

    def accept_file(user,filename,file)
        # puts "accept file from #{user} - #{filename} - #{file.path}"

        matches = @searches.keys.select{|search| search[:bot] == user and filename.index(search[:phrase].gsub(' ','_'))}
        
        if matches.empty?
            new_path = File::join( DEFAULT_PATH, filename )
            FileUtils.mv(file.path, new_path )
            return
        end 

        begin
            z = Zip::File::open( file.path )

            z.entries.each do | entry |
                books = {}
                results = z.read( entry.name ).split(/[\r\n]+/)
                results.each do | result |
                    next unless result.match(/^!.*/)
                    next unless result.match(/#{INFO}/)
                    result = result[ 0, result.index( INFO ) ].strip
                    owner, title = result.split( ' ', 2 )
                    books[ title ] = [] unless books.has_key?( title )
                    books[ title ] << owner
                end

                matches.each do | match |
                    add_results(match,books)
                    puts "New Search Results: #{match[:phrase]}"
                end
                
            end
        rescue => e
            puts e
            puts "end error"
        ensure
            file.unlink
        end
    end

end




def on_next(&block) 
    #puts "--------------------------ON NEXT"
    Timer(1,{:shots => 1}) do
        #puts "one shot--------------------------------------"
        block.call
    end 
end 

def main
    
    cli = HighLine.new

    nick = cli.ask "What is your nickname?"
    books = {}
    search_bot = nil
    bot = Cinch::Bot.new do
        #puts bot
        #puts "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        chooser = Chooser.new()
        configure do |c|
            c.server = "irc.irchighway.net"
            c.channels = [ EBOOKS ]
            c.nick = nick
        end

        on :connect do | m |
            # puts "connected: #{m}"
        end

        on :join do | m |
            if( m.user == bot.nick )
                topic = m.channel.topic.strip
                # puts "topic: #{topic}"
                # puts "oentuheontuhethuenhonteuohnutoheountuhonteuohenutohueoheuooetnh"
                search_bots = topic.split().select{ | word | word.match(/@.*/) }.collect{|bot| bot.gsub('@','').downcase }
                chooser.set_search_bots(search_bots)
                Channel( EBOOKS ).send( "hello" )
                on_next() do
                    begin
                        begin
                            chooser.choose() do | cmd |
                                puts "the command is #{cmd}"
                                if(cmd == "quit")
                                    raise "Quitting"
                                else
                                    Channel( EBOOKS ).send( cmd )
                                end
                                
                            end
                        end while true
                    rescue => e
                        puts "error: #{e}"
                    ensure
                        bot.quit
                        puts "sleeping"
                        sleep(1)
                        puts "really quitting"
                        exit
                    end
                end
                
            end
        end

        on :dcc_send do | m, dcc |
            user = m.user.nick.downcase
            # puts "------------------------------"
            # puts "dcc: #{m}"
            # puts "dcc: #{user} - #{dcc.filename}"
            
            begin
                file = Tempfile.new( dcc.filename )
                dcc.accept( file )
                file.close
                # puts user
                # puts file
                # puts "oentuheontuheonth"
                chooser.accept_file(user,dcc.filename,file)
                # puts "oentuheontuheontuhentoeuhuenothueotnho"
                # puts "------------------------------"
            
            end
        end

        on :private do | m, dcc |
            # puts "private-------------------"
            # puts m.user.nick
            # puts m.message
            chooser.parse_private_msg(m.user.nick.downcase,Sanitize(m.message))
            # puts "--------------------------"
            # if m.user
               
            #     user = m.user.nick.downcase

            #     if( user == $gSearchbot )
            #         if( m.message.index( 'Sorry' ) )
            #             puts "No Results Found"
            #             search( cli, bot )
            #         end

            #     else
            #         puts "#{m.user} - #{Sanitize(m.message)}"
            #     end
            # end
            
        end

        on :message do | m |
             #`puts "msg: #{m}"
        end

    end

    bot.loggers.level = :fatal
    bot.start
end

main
