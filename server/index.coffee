PORT    = require('./package.json').config.port
tmp     = require 'tmp'
fs      = require 'fs'
request = require 'request'
app     = require('express')()
exec 　　= require('child_process').exec

# path to compiler
mrbc =
    2: "#{__dirname}/mrbc/mrbc"
    3: "#{__dirname}/mruby/bin/mrbc"

# API uniformed header
jsonHeader =
    'Content-Type' : 'application/json; charset=UTF-8'


webCompile = (req, res) ->
    cleanup    = -> # set cleanupCallback if needed or, empty function to do nothing
    source     = '' # set source code to compile
    sourcePath = '' # set where to write source
    buildCommand = (mrbcVer, options, path) ->
        unless options then options = ''
        unless req.params.output then req.params.output = 'noname.mrb'
        options += " -o #{req.params.output}"
        # create command
        if req.query.version is '2'
            "#{mrbc[2]} #{options} #{path}"
        else # if req.query.version is '3'
            "#{mrbc[3]} #{options} #{path}"

    # start Promise
    new Promise (fulfilled, rejected) ->
        # if url given, request the content at first
        if req.query.type is 'url'
            url = req.query.content
            request url, (err, res, body) ->
                if err
                    rejected [500, 'Internal Server Error']
                else if res.statusCode isnt 200
                    rejected [404, 'Resource not found']
                else
                    source = body
                    fulfilled()

        else if req.query.type is 'source'
            source = req.query.content
            fulfilled()

        else
            rejected [400, 'Bad Request', 'Unknown resource type queried.']

    .then ->
        # ctreate a temporary file
        new Promise (fulfilled, rejected) ->
            tmp.dir (err, path, cleanupCallback) ->
                cleanup = cleanupCallback
                if err
                    rejected [500, 'Internal Server Error']
                else
                    sourcePath = path + '/source.rb'
                    fulfilled()

    .then ->
        # write content to the temporary file
        new Promise (fulfilled, rejected) ->
            fs.writeFile sourcePath, source, (err) ->
                if err
                    rejected [500, 'Internal Server Error']
                else
                    fulfilled()

    .then ->
        command = buildCommand req.query.version, req.query.options, sourcePath
        # exec
        new Promise (fulfilled, rejected) ->
            exec command, (err, stdout, stderr) ->
                if err
                    rejected [500, 'Internal Server Error']
                else if stderr
                    # maybe compile failed
                    rejected [400, 'Bad Request', 'Compile error occured.']
                else
                    # maybe compile success
                    fulfilled()

    .then ->
        new Promise (fulfilled, rejected) ->
            # send the binary
            exec "cat #{req.params.output}", (err, stdout, stderr) ->
                if err or stderr
                    console.log stderr
                    rejected [500, 'Internal Server Error']
                else
                    res.header 'Content-Type', 'application/octet-stream; charset=utf-8'
                    res.send stdout
                    fulfilled()
    .then ->
        new Promise (fulfilled, rejected) ->
            cleanup()
            fs.unlink sourcePath, fulfilled

    .catch (a) ->
        console.log a
        [statusCode, statusText, message] = a
        res.header 'Content-Type', 'application/json; charset=utf-8'
        res.json {statusCode, statusText, message}
        # after all
        cleanup()
        fs.unlink sourcePath

# get mruby version
getVersion = (req, res) ->
    # specify bytecode format
    if req.query.format is 2
        format = 2
    else
        format = 3
    # do command
    exec "#{mrbc[format]} -v", (err, stdout, stderr) ->
        if err and stderr
            stdout = stdout.split("\n")[0]
            res.set(jsonHeader).status(200).json {
                success: true
                information: stdout
            }
        else
            res.set(jsonHeader).status(500).json {
                success: false
                message: 'Internal Server Error'
            }

app.get '/', webCompile
app.get '/version/', getVersion

app.listen PORT, ->
    console.log "Server is listening on port #{PORT}."


###
  def send_mrb( pathrbname, opt )
    if(opt.include?("--verbose")==true || opt.include?("-v")==true || opt.include?("-o")==true ) then
      @compiler.destroy
      render action: "new"
      return
    end

    if(opt.include?("--")==true) then
      o, e, s = Open3.capture3("mrbc " + opt + " >&2")
      redirect_to @compiler, notice: e.to_s + ' ' + s.to_s
      @compiler.destroy
      return
    end


    fullpath = Rails.root.to_s + "/public" + File.dirname(pathrbname) + "/"

	bname = File.basename(pathrbname).downcase
	if( bname!=File.basename(pathrbname) )then
		File.rename( fullpath + File.basename(pathrbname), fullpath + bname )
	end

    rbfile = File.basename(bname)
    mrbfile = File.basename(bname, ".rb") + ".mrb"
    cfile = File.basename(bname, ".rb") + ".c"

    #o, e, s = Open3.capture3("cd " + fullpath + "; mrbc " + opt + " -o" + mrbfile + " " + rbfile + " >&2")
    o, e, s = Open3.capture3("cd " + fullpath + "; mrbc " + opt + " " + rbfile + " >&2")
    if( e==''  ) then
      if( opt.include?("-B")==true )then
        mrb_data = File.binread(fullpath + cfile)
        send_data(mrb_data, filename: cfile, type: "application/octet-stream", disposition: "inline")
      else
        mrb_data = File.binread(fullpath + mrbfile)
        send_data(mrb_data, filename: mrbfile, type: "application/octet-stream", disposition: "inline")
      end
    else
      redirect_to @compiler, notice: e.to_s + ' ' + s.to_s
    end

    @compiler.destroy
    deleteall( fullpath )
  end
###
