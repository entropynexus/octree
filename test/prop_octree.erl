-module(prop_octree).
-include_lib("proper/include/proper.hrl").

% Properties

prop_test() ->
    Tree = octree:create({0, 0, 0}, {100, 100, 100}),
    ?FORALL(
        {Point},
        {point()},
        begin
            Tree1 = octree:insert(Tree, Point),
            octree:find(Tree1, Point)
        end
    ).

% Generators

coordinate() ->
    range(1, 99).
point() ->
    {coordinate(), coordinate(), coordinate()}.
