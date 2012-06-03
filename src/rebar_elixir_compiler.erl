%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
%% -------------------------------------------------------------------
%%
%% rebar: Erlang Build Tools
%%
%% Copyright (c) 2009, 2010 Dave Smith (dizzyd@dizzyd.com)
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% -------------------------------------------------------------------
-module(rebar_elixir_compiler).

-export([compile/2,
         clean/2,
         pre_eunit/2]).

-export([dotex_compile/2,
         dotex_compile/3]).

%% ===================================================================
%% Public API
%% ===================================================================

%% Supported configuration variables:
%%
%% * ex_first_files - First elixir files to compile
%% * elixir_opts - Erlang list of elixir compiler options
%%                 
%%                 For example, {elixir_opts, [{ignore_module_conflict, false}]}
%%

-spec compile(Config::rebar_config:config(), AppFile::file:filename()) -> 'ok'.
compile(Config, _AppFile) ->
    dotex_compile(Config, "ebin").

-spec clean(Config::rebar_config:config(), AppFile::file:filename()) -> 'ok'.
clean(_Config, _AppFile) ->
    BeamFiles = rebar_utils:find_files("ebin", "^.*\\.beam\$"),
    rebar_file_utils:delete_each(BeamFiles),
    lists:foreach(fun(Dir) -> delete_dir(Dir, dirs(Dir)) end, dirs("ebin")),
    ok.


-spec pre_eunit(Config::rebar_config:config(), AppFile::file:filename()) -> 'ok'.
pre_eunit(Config, _AppFIle) ->
    dotex_compile(Config, ".eunit").

%% ===================================================================
%% .ex Compilation API
%% ===================================================================

-spec dotex_compile(Config::rebar_config:config(),
                     OutDir::file:filename()) -> 'ok'.
dotex_compile(Config, OutDir) ->
    dotex_compile(Config, OutDir, []).

dotex_compile(Config, OutDir, MoreSources) ->
    case application:load(elixir) of
        ok ->
            application:start(elixir),
            FirstExs = rebar_config:get_list(Config, ex_first_files, []),
            ExOpts = ex_opts(Config),
            %% Support the src_dirs option allowing multiple directories to
            %% contain elixir source. This might be used, for example, should
            %% eunit tests be separated from the core application source.
            SrcDirs = src_dirs(proplists:append_values(src_dirs, ExOpts)),
            RestExs  = [Source || Source <- gather_src(SrcDirs, []) ++ MoreSources,
                                  not lists:member(Source, FirstExs)],
            
            NewFirstExs = FirstExs,
            
            %% Make sure that ebin/ exists and is on the path
            ok = filelib:ensure_dir(filename:join("ebin", "dummy.beam")),
            CurrPath = code:get_path(),
            true = code:add_path(filename:absname("ebin")),
            rebar_base_compiler:run(Config, NewFirstExs, RestExs,
                                    fun(S, C) ->
                                            internal_ex_compile(S, C, OutDir, ExOpts)
                                    end),
            true = code:set_path(CurrPath),
            application:stop(elixir),
            ok;
        _ ->
            rebar_log:log(info, "No Elixir compiler found~n", [])
    end.


%% ===================================================================
%% Internal functions
%% ===================================================================

ex_opts(Config) ->
    rebar_config:get(Config, ex_opts, [{ignore_module_conflict, true}]).

-spec internal_ex_compile(Source::file:filename(),
                           Config::rebar_config:config(),
                           Outdir::file:filename(),
                           ExOpts::list()) -> 'ok' | 'skipped'.
internal_ex_compile(Source, _Config, Outdir, ExOpts) ->
    '__MAIN__.Code':compiler_options(orddict:from_list(ExOpts)),
    try
        elixir_compiler:file_to_path(Source, Outdir),
        ok
    catch _:{'__MAIN__.CompileError',_, Reason,File,Line} ->
            rebar_log:log(error, "Elixir compiler failed with:  ~s in ~s:~w~n",[Reason,File,Line]),
            throw({error, failed})
    end.

gather_src([], Srcs) ->
    Srcs;
gather_src([Dir|Rest], Srcs) ->
    gather_src(Rest, Srcs ++ rebar_utils:find_files(Dir, ".*\\.ex\$")).

-spec src_dirs(SrcDirs::[string()]) -> [file:filename(), ...].
src_dirs([]) ->
    ["src","lib"];
src_dirs(SrcDirs) ->
    SrcDirs.

-spec dirs(Dir::file:filename()) -> [file:filename()].
dirs(Dir) ->
    [F || F <- filelib:wildcard(filename:join([Dir, "*"])), filelib:is_dir(F)].

-spec delete_dir(Dir::file:filename(),
                 Subdirs::[string()]) -> 'ok' | {'error', atom()}.
delete_dir(Dir, []) ->
    file:del_dir(Dir);
delete_dir(Dir, Subdirs) ->
    lists:foreach(fun(D) -> delete_dir(D, dirs(D)) end, Subdirs),
    file:del_dir(Dir).
