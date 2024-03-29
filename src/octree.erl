% @doc Octree data stucture.
-module(octree).

-export([
    create/2,
    delete/1,
    insert/2,
    find/2,
    to_dot/1
]).

-record(octree, {
    % @todo
    % Temporarily supporting multiple backend while I figure out the most
    % efficient implementation.
    % @end
    backend :: digraph,
    tree :: digraph:graph()
}).
-type t() :: #octree{}.

-type coordinate() :: integer().

-type point() :: {X :: coordinate(), Y :: coordinate(), Z :: coordinate()}.

-type edge_label() ::
    top_left_front
    | top_right_front
    | bottom_right_front
    | bottom_left_front
    | top_left_back
    | top_right_back
    | bottom_right_back
    | bottom_left_back.

-record(region, {
    top_left_front :: point(),
    bottom_right_back :: point()
}).

-type node_type() :: empty | point() | #region{}.

-export_type([t/0, point/0]).

% @doc Creates a new octree.
-spec create(TopLeftFront :: point(), BottomRightBack :: point()) -> t().
create(TopLeftFront, BottomRightBack) ->
    Tree = digraph:new([acyclic, protected]),
    RootLabel = #region{
        top_left_front = TopLeftFront,
        bottom_right_back = BottomRightBack
    },
    RootID = digraph:add_vertex(Tree),
    digraph:add_vertex(Tree, RootID, RootLabel),
    create_children(Tree, RootID),
    true = digraph_utils:is_tree(Tree),
    {yes, RootID} = digraph_utils:arborescence_root(Tree),
    #octree{
        backend = digraph,
        tree = Tree
    }.

% @doc Deletes an octree.
-spec delete(t()) -> ok.
delete(#octree{backend = digraph, tree = Tree}) ->
    true = digraph:delete(Tree),
    ok.

% @doc Inserts a point in the Octree.
%
% The the following logic is used:
% <ol>
% 	<li>Start with root node as current node.</li>
% 	<li>If the given point is not in cuboid represented by current node,
%    stop insertion with error.</li>
% 	<li>Determine the appropriate child node to store the point.</li>
% 	<li>If the child node is empty node, replace it with a point node representing
%    the point. Stop insertion.</li>
% 	<li>If the child node is a point node, replace it with a region node.
%    Call insert for the point that just got replaced.<br/> Set current node as the
%    newly formed region node.</li>
% 	<li>If selected child node is a region node, set the child node as current node.
%    Goto step 2.</li>
% </ol>
% @end
-spec insert(Octree :: t(), Point :: point()) -> t() | outside.
insert(#octree{backend = digraph, tree = Tree} = Octree, Point) ->
    {yes, Root} = digraph_utils:arborescence_root(Tree),
    {Root, Label} = digraph:vertex(Tree, Root),
    insert_in(Octree, Point, root, Root, Label).

-spec insert_in(t(), point(), digraph:label(), digraph:vertex(), node_type()) -> outside | ok.
insert_in(
    #octree{tree = Tree} = Octree,
    Point,
    _EdgeLabel,
    Position,
    #region{top_left_front = TLF, bottom_right_back = BRB} = Region
) ->
    case outside(Point, TLF, BRB) of
        true ->
            outside;
        false ->
            logger:debug("Insert in region: ~w Pos: ~w Reg: ~w", [
                Point,
                Position,
                Region
            ]),
            NextEdgeLabel = next_edge_label(Point, middle(TLF, BRB)),
            logger:debug("NextEdgeLabel: ~w", [NextEdgeLabel]),
            Edges = digraph:out_edges(Tree, Position),
            {NextVertex, NextVertexLabel} = next_vertex(Tree, NextEdgeLabel, Edges),
            logger:debug("RegNextVertexLabel: ~w", [NextVertexLabel]),
            insert_in(Octree, Point, NextEdgeLabel, NextVertex, NextVertexLabel)
    end;
insert_in(#octree{backend = digraph, tree = Tree} = Octree, Point, EdgeLabel, Position, empty) ->
    logger:debug("Insert in empty: ~w", [EdgeLabel]),
    digraph:add_vertex(Tree, Position, Point),
    Octree;
insert_in(#octree{backend = digraph, tree = Tree} = Octree, Point, EdgeLabel, Position, _Label) ->
    logger:debug("Insert in point: ~w Pos: ~w", [Point, Position]),
    [ParentVertex] = digraph:in_neighbours(Tree, Position),
    {
        ParentVertex,
        #region{top_left_front = TLF, bottom_right_back = BRB}
    } = digraph:vertex(Tree, ParentVertex),
    NewRegion = edge_label_to_region(EdgeLabel, TLF, BRB, middle(TLF, BRB)),
    logger:debug("NewRegion: ~w", [NewRegion]),
    NewRegionID = digraph:add_vertex(Tree, Position, NewRegion),
    create_children(Tree, NewRegionID),

    Edges = digraph:out_edges(Tree, Position),

    NextEdgeLabel = next_edge_label(
        Point, middle(NewRegion#region.top_left_front, NewRegion#region.bottom_right_back)
    ),
    {NextVertex, NextVertexLabel} = next_vertex(Tree, NextEdgeLabel, Edges),
    logger:debug("NextVertexLabel: ~w", [NextVertexLabel]),
    insert_in(Octree, Point, NextEdgeLabel, NextVertex, NextVertexLabel).

edge_label_to_region(
    top_left_front,
    TopLeftFront,
    _BackRightBack,
    Middle
) ->
    #region{
        top_left_front = TopLeftFront,
        bottom_right_back = Middle
    };
edge_label_to_region(
    top_right_front,
    {_TLFX, TLFY, TLFZ},
    {BRBX, _BRBY, _BRBZ},
    {MidX, MidY, MidZ}
) ->
    #region{
        top_left_front = {MidX + 1, TLFY, TLFZ},
        bottom_right_back = {BRBX, MidY, MidZ}
    };
edge_label_to_region(
    bottom_right_front,
    {_TLFX, _TLFY, TLFZ},
    {BRBX, BRBY, _BRBZ},
    {MidX, MidY, MidZ}
) ->
    #region{
        top_left_front = {MidX + 1, MidY + 1, TLFZ},
        bottom_right_back = {BRBX, BRBY, MidZ}
    };
edge_label_to_region(
    bottom_left_front,
    {TLFX, _TLFY, TLFZ},
    {_BRBX, BRBY, _BRBZ},
    {MidX, MidY, MidZ}
) ->
    #region{
        top_left_front = {TLFX, MidY + 1, TLFZ},
        bottom_right_back = {MidX, BRBY, MidZ}
    };
edge_label_to_region(
    top_left_back,
    {TLFX, TLFY, _TLFZ},
    {_BRBX, _BRBY, BRBZ},
    {MidX, MidY, MidZ}
) ->
    #region{
        top_left_front = {TLFX, TLFY, MidZ + 1},
        bottom_right_back = {MidX, MidY, BRBZ}
    };
edge_label_to_region(
    top_right_back,
    {_TLFX, TLFY, _TLFZ},
    {BRBX, _BRBY, BRBZ},
    {MidX, MidY, MidZ}
) ->
    #region{
        top_left_front = {MidX + 1, TLFY, MidZ + 1},
        bottom_right_back = {BRBX, MidY, BRBZ}
    };
edge_label_to_region(
    bottom_right_back,
    _TLF,
    BRB,
    {MidX, MidY, MidZ}
) ->
    #region{
        top_left_front = {MidX + 1, MidY + 1, MidZ + 1},
        bottom_right_back = BRB
    };
edge_label_to_region(
    bottom_left_back,
    {TLFX, _TLFY, _TLFZ},
    {_BRBX, BRBY, BRBZ},
    {MidX, MidY, MidZ}
) ->
    #region{
        top_left_front = {TLFX, MidY + 1, MidZ + 1},
        bottom_right_back = {MidX, BRBY, BRBZ}
    }.

% @doc Finds a point in the Octree.
%
% The following logic is used:
% <ol>
% 	<li>Start with root node as current node.</li>
%		<li>If the given point is not in boundary represented by current node, stop
%    search with error.</li>
% 	<li>Determine the appropriate child node to store the point.</li>
% 	<li>If the child node is empty node, return FALSE.</li>
% 	<li>If the child node is a point node and it matches the given point return
%    TRUE, otherwise return FALSE.</li>
% 	<li>If the child node is a region node, set current node as the child
%    region node. Goto step 2.</li>
% </ol>
% @end
% @todo change arguments order to match insert.
-spec find(Octree :: t(), Point :: point()) -> boolean().
find(#octree{backend = digraph, tree = Tree} = Octree, Point) ->
    {yes, Root} = digraph_utils:arborescence_root(Tree),
    {Root, Label} = digraph:vertex(Tree, Root),
    find_in(Octree, Label, Root, Point).

-spec find_in(t(), node_type(), digraph:vertex(), point()) -> boolean().
find_in(
    #octree{tree = Tree} = Octree,
    #region{top_left_front = TLF, bottom_right_back = BRB},
    Position,
    Point
) ->
    case outside(Point, TLF, BRB) of
        true ->
            false;
        false ->
            logger:debug("Searching: ~w", [Point]),
            NextEdgeLabel = next_edge_label(Point, middle(TLF, BRB)),
            logger:debug("NextEdgeLabel: ~w", [NextEdgeLabel]),
            Edges = digraph:out_edges(Tree, Position),
            {NextVertex, NextVertexLabel} = next_vertex(Tree, NextEdgeLabel, Edges),
            logger:debug("NextVertex: ~w Label: ~w", [NextVertex, NextVertexLabel]),
            find_in(Octree, NextVertexLabel, NextVertex, Point)
    end;
find_in(_Octree, empty, _Position, _Point) ->
    false;
find_in(_Octree, PointA, _Position, PointB) ->
    equal(PointA, PointB).

-spec next_edge_label(Point :: point(), Middle :: point()) -> edge_label().
next_edge_label({X, Y, Z}, {Xm, Ym, Zm}) when X =< Xm, Y =< Ym, Z =< Zm ->
    top_left_front;
next_edge_label({X, Y, Z}, {Xm, Ym, Zm}) when X =< Xm, Y =< Ym, Z > Zm ->
    top_left_back;
next_edge_label({X, Y, Z}, {Xm, Ym, Zm}) when X =< Xm, Y > Ym, Z =< Zm ->
    bottom_left_front;
next_edge_label({X, Y, Z}, {Xm, Ym, Zm}) when X =< Xm, Y > Ym, Z > Zm ->
    bottom_left_back;
next_edge_label({X, Y, Z}, {Xm, Ym, Zm}) when X > Xm, Y =< Ym, Z =< Zm ->
    top_right_front;
next_edge_label({X, Y, Z}, {Xm, Ym, Zm}) when X > Xm, Y =< Ym, Z > Zm ->
    top_right_back;
next_edge_label({X, Y, Z}, {Xm, Ym, Zm}) when X > Xm, Y > Ym, Z =< Zm ->
    bottom_right_front;
next_edge_label({X, Y, Z}, {Xm, Ym, Zm}) when X > Xm, Y > Ym, Z > Zm ->
    bottom_right_back.

-spec next_vertex(digraph:graph(), edge_label(), [digraph:edge()]) ->
    {digraph:vertex(), digraph:label()}
    | not_found.
next_vertex(_Tree, _NextLabel, []) ->
    not_found;
next_vertex(Tree, NextLabel, [Edge | Rest]) ->
    {Edge, _V1, V2, Label} = digraph:edge(Tree, Edge),
    case Label =:= NextLabel of
        true ->
            digraph:vertex(Tree, V2);
        false ->
            next_vertex(Tree, NextLabel, Rest)
    end.

-spec create_children(digraph:graph(), #region{}) -> digraph:graph().
create_children(Graph, Node) ->
    create_children(Graph, Node, edge_labels()).

create_children(Graph, NodeID, [Label | Rest]) ->
    ChildID = digraph:add_vertex(Graph),
    digraph:add_vertex(Graph, ChildID, empty),
    digraph:add_edge(Graph, NodeID, ChildID, Label),
    create_children(Graph, NodeID, Rest);
create_children(_Graph, _NodeID, []) ->
    ok.

edge_labels() ->
    [
        top_left_front,
        top_right_front,
        bottom_right_front,
        bottom_left_front,
        top_left_back,
        top_right_back,
        bottom_right_back,
        bottom_left_back
    ].

% @doc Wether or not a point is outside a cube.
-spec outside(Point :: point(), TopLeftFront :: point(), BottomRightBack :: point()) -> boolean().
outside({X, Y, Z}, {Xa, Ya, Za}, {Xb, Yb, Zb}) ->
    X < Xa orelse X > Xb orelse
        Y < Ya orelse Y > Yb orelse
        Z < Za orelse Z > Zb.

% @doc Returns the middle point between two points.
-spec middle(PointA :: point(), PointB :: point()) -> point().
middle({Xa, Ya, Za}, {Xb, Yb, Zb}) ->
    {
        floor((Xa + Xb) / 2),
        floor((Ya + Yb) / 2),
        floor((Za + Zb) / 2)
    }.

% @doc Wether two points are equal.
-spec equal(point(), point()) -> boolean().
equal({Xa, Ya, Za}, {Xb, Yb, Zb}) ->
    Xa =:= Xb andalso Ya =:= Yb andalso Za =:= Zb.

to_dot(#octree{backend = digraph, tree = Tree}) ->
    digraph_dot:convert(Tree, "OCTree").
