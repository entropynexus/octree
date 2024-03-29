#!/usr/bin/env escript
%%! +pc unicode -pa .build/default/lib/erlperf/ebin -pa .build/default/lib/octree/ebin

-mode(compile).

main(_) ->
   Report = erlperf:benchmark([
			#{
				init_runner => "octree:create({0, 0, 0}, {100, 100, 100}).", 
				runner => "run(_Init, Tree) -> octree:insert(Tree, {10, 10, 10})."
			}
		], #{report => full}, undefined),
		Out = erlperf_cli:format(Report, #{
			format => extended,
			viewport_width => 120
		}),
		io:format(Out),
		halt(0).
