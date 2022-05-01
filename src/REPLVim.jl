module REPLVim

using Sockets
using Logging
using REPL
using JSON3
using StructTypes

abstract type Command end

struct EvalCommand <: Command
  type::String
  id::Int32
  code::String
end

struct InputCommand <: Command
  type::String
  id::Int32
  code::String
end

struct CompleteCommand <: Command
  type::String
  id::Int32
  full::String
  partial::String
end

struct ExitCommand <: Command
  type::String
  id::Int32
end

struct InterruptCommand <: Command
  type::String
  id::Int32
end

StructTypes.StructType(::Type{Command}) = StructTypes.AbstractType()
StructTypes.StructType(::Type{EvalCommand}) = StructTypes.Struct()
StructTypes.StructType(::Type{InputCommand}) = StructTypes.Struct()
StructTypes.StructType(::Type{CompleteCommand}) = StructTypes.Struct()
StructTypes.StructType(::Type{ExitCommand}) = StructTypes.Struct()
StructTypes.StructType(::Type{InterruptCommand}) = StructTypes.Struct()
StructTypes.subtypekey(::Type{Command}) = :type
StructTypes.subtypes(::Type{Command}) =
  (eval=EvalCommand,
   input=InputCommand,
   complete=CompleteCommand,
   interrupt=InterruptCommand,
   exit=ExitCommand)

mutable struct Session
  socket
  display_properties::Dict
  in_module::Module
end

function sprint_ctx(f, session)
  io = IOBuffer()
  ctx = IOContext(io, :module=>session.in_module, session.display_properties...)
  f(ctx)
  String(take!(io))
end

function execute_command(session::Session, cmd::EvalCommand)
  sprint_ctx(session) do io
    with_logger(ConsoleLogger(io)) do
      expr = Meta.parse(cmd.code)
      result = Base.eval(session.in_module, expr)
      if result !== nothing
        Base.invokelatest(show, io, MIME"text/plain"(), result)
      end
    end
  end
end
function execute_command(session::Session, cmd::InputCommand)
  sprint_ctx(session) do io
    with_logger(ConsoleLogger(io)) do
      repl = Base.active_repl
      juliamode = repl.interface.modes[1]
      juliamodestate = repl.mistate.mode_state[juliamode]
      REPL.LineEdit.edit_insert(juliamodestate, cmd.code)
      REPL.LineEdit.commit_line(repl.mistate)
      juliamode.on_done(repl.mistate,
                        REPL.LineEdit.buffer(repl.mistate), true)
    end
  end
end
function execute_command(session::Session, cmd::CompleteCommand)
  ret, range, should_complete = REPL.completions(cmd.full, lastindex(cmd.partial),
                                                  session.in_module)
  (unique!(map(REPL.completion_text, ret)), cmd.partial[range], should_complete)
end

function serve_session(session)
  socket = session.socket
  flush(socket)
  @sync begin
    commands = Channel{Command}(1)
    responses = Channel{Any}(1)

    executor = @async try
      while true
        cmd =
          try
            take!(commands)
          catch exc
            if exc isa InvalidStateException && !isopen(commands)
              break
            else
              rethrow()
            end
          end
        try
          result = execute_command(session, cmd)
          if result !== nothing
            put!(responses,
                 Dict(:ok => result, :id => cmd.id))
          end
        catch exc
          if exc isa InterruptException
            continue
          else
            put!(responses,
                 Dict(:error => sprint(showerror, exc), :id => cmd.id))
          end
        end
      end
    catch exc
      @error "RemoteREPL backend crashed" exception=exc,catch_backtrace()
    finally
      close(responses)
    end

    @async try
      while true
        response = take!(responses)
        JSON3.write(socket, response)
        write(socket, "\n")
      end
    catch exc
      if isopen(responses) && isopen(socket)
        rethrow()
      end
    finally
      close(socket)
    end

    try
      while isopen(socket)
        cmd = nothing
        try
          line = readline(socket)
          cmd = JSON3.read(line, Command)
        catch exc
          put!(responses, Dict(:error=>"invalid cmd"))
          continue
        end
        @debug "Client cmd" cmd
        if cmd isa ExitCommand
          break
        elseif cmd isa InterruptCommand
          schedule(executor, InterruptException(); error=true)
        else
          put!(commands, cmd)
        end
      end
    catch exc
      @error "RemoteREPL frontend crashed" exception=exc,catch_backtrace()
      rethrow()
    finally
      close(socket)
      close(commands)
    end
  end
end

serve(host=Sockets.localhost, port::Integer=2345; kws...) =
  let server = listen(host, port)
    try
      @info "REPL server on $host:$port"
      serve(server; kws...)
    finally
      close(server)
    end
  end

serve(port::Integer; kws...) =
  serve(Sockets.localhost, port; kws...)

function serve(server::Base.IOServer)
  open_sessions = Set{Session}()
  @sync try
    while isopen(server)
      socket = accept(server)
      session = Session(socket, Dict(), Main)
      push!(open_sessions, session)
      peer = getpeername(socket)
      @async try
        serve_session(session)
      catch exc
        if !(exc isa EOFError && !isopen(session.socket))
          @warn "Something went wrong evaluating client command" #=
              =# exception=exc,catch_backtrace()
        end
      finally
        @info "REPL client exited"
        close(session.socket)
        pop!(open_sessions, session)
      end
      @info "REPL client connected"
    end
  catch exc
    if exc isa Base.IOError && !isopen(server)
      # Ok - server was closed
      return
    end
    @error "Unexpected server failure" isopen(server) exception=exc,catch_backtrace()
    rethrow()
  finally
    for session in open_sessions
      close(session.socket)
    end
  end
end

end
