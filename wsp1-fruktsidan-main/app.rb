require 'sinatra'
require 'securerandom'
require 'fiddle'



class App < Sinatra::Base

    # Funktion för att prata med databasen
    # Exempel på användning: db.execute('SELECT * FROM fruits')
  enable :sessions

    def db
      return @db if @db

      @db = SQLite3::Database.new("db/fruits.sqlite")
      @db.results_as_hash = true

      
      return @db
    end



    #Kollar igenom alla fruitid's inuti arrayen för att se om den redan finns
    def checkFruitId(fruitInfo, fruitId)
      return false if fruitInfo ==[]
      fruitInfo.each do |i|
        return true if i[0] == fruitId
      end
      return false
    end

    #Funktion för att sätta ihop en sönder plockad array från formen: a = [[x,y], [z,a]] -> a = "x:y z:a"
    def arrayIntoCDB(array)
      newstring = ""
      array.each do |i|
        newstring += "#{i[0]}:#{i[1]} "
      end
      return newstring
    end

    def find_count(fruitId)
      count = 0

      @customerinfo = db.execute('SELECT DISTINCT * FROM customerinfo WHERE customerId=?', session['session_id']).first
  
      customerinfo = @customerinfo['selectedFruit']

      fruitInfo = customerinfo.dup.chomp.split(" ").map{|s| s.split(":")}

      fruitInfo.each do |i|
        if i[0] == fruitId
          count = i[1]
        end
      end
      return count
    end



    #Uppdaterar en specifik frukts antal till count
    def updateCount(fruitInfo, fruitid, count)
      newFruitInfo = fruitInfo.dup
      fruitInfo.each_with_index do |info, i|
        if info[0] == fruitid
          newFruitInfo[i][1] = count  
          return arrayIntoCDB(newFruitInfo)
        end
      end
      raise "Fanns inte en frukt med id:t: #{fruitid} i arrayen: #{fruitInfo}"
    end

    
    # Routen gör en redirect till '/fruits'
    get '/' do
        redirect('/fruits')
    end
    use Rack::Session::Cookie,  :key => 'SESSION_ID'
                          
    before do   # Before every request, make sure they get assigned an ID.
        session[:id] ||= SecureRandom.uuid
        
    end

    #Routen hämtar alla frukter i databasen
    get '/fruits' do
      @fruits = db.execute('SELECT * FROM fruits')
      @customers = db.execute('SELECT DISTINCT customerId FROM customerinfo')
      alreadyExisting = false

      db.execute("INSERT INTO customerinfo (customerId) VALUES (?)", [session['session_id']]) if @customers == [  ]
      @customers.each do |i|

        if i["customerId"] == session['session_id']
          alreadyExisting = true
          break
        end
      end
      if alreadyExisting == false
        db.execute("INSERT INTO customerinfo (customerId) VALUES (?)", session['session_id'])
      end



      erb(:"fruits/index")
    end


    # Routen visar ett formulär för att spara en ny frukt till databasen.
    get '/fruits/new' do
      erb(:"fruits/new")
    end

    #Routen visar din varukorg
    get '/fruits/cart' do 
      @fruitsId = db.execute("SELECT id FROM fruits")
  
      @cartInfo = db.execute("SELECT DISTINCT selectedFruit FROM customerinfo WHERE customerId=?", session['session_id']).first["selectedFruit"]
      cartinfo = @cartInfo.chomp.split(" ").map{|s| s.split(":")}
      
      @cartArray = []

      cartinfo.each do |info|
        @fruitsId.each do |id|
          if id["id"].to_s == info[0]
            
            @cartArray << [db.execute("SELECT name FROM fruits WHERE id=?", id["id"]).first["name"], info[1]]

          end
        end
      end


      erb(:"fruits/cart")
    end

    # Routen sparar en frukt till databasen och gör en redirect till '/fruits'.
    post '/fruits' do
      #todo: Läs ut fruit_name & fruit_description från params
      fruit_name = params["fruit_name"]
      fruit_description = params["fruit_description"]
      fruit_taste = params["fruit_taste"]
      #todo: Lägg till den nya frukten i databasen
      db.execute(
        "INSERT INTO fruits (name, tastiness, description) VALUES (?,?,?)",
        [fruit_name, fruit_taste,fruit_description]
      )
      
      redirect "/fruits"
    end

    # Routen visar all info (från databasen) om en frukt
    get '/fruits/:id' do | id |
      #todo välj ut frukten med it:t
      #Visa i rätt ERB-fil
      @fruit = db.execute('SELECT * FROM fruits WHERE id=?', id).first
      @count = find_count(id)
      erb(:"fruits/show")
    end

    # Routen tar bort frukten med id
    get '/fruits/:id/delete' do | id |
      #todo: Ta bort frukten i databasen med id:t
      @fruit = db.execute('SELECT * FROM fruits WHERE id=?', id).first

      db.execute("DELETE FROM fruits WHERE id=?", id)

      redirect("/fruits")

    end

    post '/fruits/:id/addtocart' do | id |
      #todo: Ta bort frukten i databasen med id:t
      @fruit = db.execute('SELECT * FROM fruits WHERE id=?', id).first

      count = (params['count'] || "").to_s.strip
      halt 400, "antal krävs" if count.empty?
      @customerinfo = db.execute('SELECT DISTINCT * FROM customerinfo WHERE customerId=?', session['session_id']).first
  
      customerinfo = @customerinfo['selectedFruit']
      customerinfo = "" if customerinfo == nil
      fruitInfo = customerinfo.dup.chomp.split(' ').map{|i| i.split(':')}



      if !checkFruitId(fruitInfo, id)
        customerinfo += "#{id}:#{count} "

        db.execute("UPDATE customerinfo SET selectedFruit=? WHERE customerId=?", [customerinfo, session['session_id']])
      elsif checkFruitId(fruitInfo, id)
        db.execute("UPDATE customerinfo SET selectedFruit=? WHERE customerId=?", [updateCount(fruitInfo, id, count), session['session_id']])
      end

      redirect("/fruits/cart")

    end

    # Routen visar ett formulär på edit.erb för att ändra frukten med id
    get '/fruits/:id/edit' do | id |
      # todo: Hämta info (från databasen) om frukten med id
      @fruit = db.execute('SELECT * FROM fruits WHERE id=?', id).first

      # todo: Visa infon i fruits/edit.erb
      erb(:"fruits/edit")
    end

    # Routen sparar ändringarna från formuläret
    post "/fruits/:id/update" do | id |
      @fruit = db.execute('SELECT * FROM fruits WHERE id=?', id).first
      # todo: Läs name & category från formuläret
      fruit_name = params["fruit_name"] if params["fruit_name"].chomp != ""
      fruit_name = @fruit['name'] if params["fruit_name"].chomp == ""
      fruit_description = params["fruit_description"] if params["fruit_description"].chomp != ""
      fruit_description = @fruit['description'] if params["fruit_description"].chomp == ""
      fruit_taste = params["fruit_taste"] if params["fruit_taste"].chomp != ""
      fruit_taste = @fruit['tastiness'] if params["fruit_taste"].chomp == ""
      # todo: Kör SQL för att uppdatera datan från formuläret

      db.execute("UPDATE fruits SET name = ?, tastiness = ?, description = ? WHERE id = ?",
      [fruit_name, fruit_taste, fruit_description, id])

      redirect "/fruits/#{id}"
    end


    get '/login' do
      erb(:"/login")
    end

    get '/signup' do
      erb(:"/signup")
    end

    
    post '/login' do
      redirect('/fruits')
    end

    post '/signup' do
      redirect('/fruits')    
    end

    
    
end
