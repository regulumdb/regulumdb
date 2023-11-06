:- module('query/definition',[
              mode/2,
              definition/1,
              cost/2,
              is_var/1,
              non_var/1
          ]).

is_var(v(_)).

non_var(X) :- \+ is_var(X).

/* Query level, aggregation and metalogic */
definition(
    ';'{
        name: 'Or',
        fields: [or],
        mode: [+],
        types: [list(query)]
    }).
definition(
    ','{
        name: 'And',
        fields: [and],
        mode: [+],
        types: [list(query)]
    }).
definition(
    immediately{
        name: 'Immediately',
        fields: [query],
        mode: [+],
        types: [query]
    }).
definition(
    opt{
        name: 'Optional',
        fields: [query],
        mode: [+],
        types: [query]
    }).
definition(
    once{
        name: 'Once',
        fields: [query],
        mode: [+],
        types: [query]
    }).
definition(
    select{
        name: 'Select',
        fields: [variables,query],
        mode: [+,+],
        types: [list(string),query]
    }).
definition(
    start{
        name: 'Start',
        fields: [start,query],
        mode: [+,+],
        types: [integer,query]
    }).
definition(
    limit{
        name: 'Limit',
        fields: [limit,query],
        mode: [+,+],
        types: [integer,query]
    }).
definition(
    count{
        name: 'Count',
        fields: [query,count],
        mode: [+,?],
        types: [query,count]
    }).
definition(
    order_by{
        name: 'OrderBy',
        fields: [ordering,query],
        mode: [+,+],
        types: [list(order),query]
    }).
definition(
    opt{
        name: 'Optional',
        fields: [query],
        mode: [+],
        types: [query]
    }).
definition(
    not{
        name: 'Not',
        fields: [query],
        mode: [+],
        types: [query]
    }).
definition(
    group_by{
        name: 'GroupBy',
        fields: [template,group_by,value,query],
        mode: [+,+,?,+],
        types: [value,template,data_value,query]
    }).
definition(
    distinct{
        name: 'Distinct',
        fields: [variables,query],
        mode: [+,+],
        types: [list(string),query]
    }).


/* collection selection */
definition(
    using{
        name: 'Using',
        fields: [collection,query],
        mode: [+,+],
        types: [collection,query]
    }).
definition(
    from{
        name: 'From',
        fields: [graph,query],
        mode: [+,+],
        types: [graph,query]
    }).
definition(
    into{
        name: 'Into',
        fields: [graph,query],
        mode: [+,+],
        types: [graph,query]
    }).

/* documents */
definition(
    get_document{
        name: 'ReadDocument',
        fields: [identifier,document],
        mode: [+,?],
        types: [node,json]
    }).
definition(
    replace_document{
        name: 'UpdateDocument',
        fields: [document,optional(identifier)],
        mode: [+,?],
        types: [node,json]
    }).
definition(
    insert_document{
        name: 'InsertDocument',
        fields: [document,optional(identifier)],
        mode: [+,?],
        types: [node,json]
    }).
definition(
    delete_document{
        name: 'DeleteDocument',
        fields: [identifier],
        mode: [+],
        types: [node]
    }).
/* Triples */
definition(
    delete{
        name: 'DeleteTriple',
        fields: [subject,predicate,object,optional(graph)],
        mode: [+,+,+,+],
        types: [node,node,value,graph]
    }).
definition(
    addition{
        name: 'AddedTriple',
        fields: [subject,predicate,object,optional(graph)],
        mode: [?,?,?,+],
        types: [node,node,value,graph]
    }).
definition(
    removal{
        name: 'DeletedTriple',
        fields: [subject,predicate,object,optional(graph)],
        mode: [?,?,?,+],
        types: [node,node,value,graph]
    }).
definition(
    t{
        name: 'Triple',
        fields: [subject,predicate,object,optional(graph)],
        mode: [?,?,?,+],
        types: [node,node,value,graph]
    }).
definition(
    path{
        name: 'Path',
        fields: [subject,pattern,object,optional(path)],
        mode: [?,+,?,-],
        types: [node,pattern,node,json]
    }).
definition(
    insert{
        name: 'AddTriple',
        fields: [subject,predicate,object,optional(graph)],
        mode: [+,+,+,+],
        types: [node,node,value,graph]
    }).
/* operators */
definition(
    ={
        name: 'Equals',
        fields: [left,right],
        mode: [+,+],
        types: [any,any]
    }).
definition(
    <{
        name: 'Less',
        fields: [left,right],
        mode: [+,+],
        types: [any,any]
    }).
definition(
    >{
        name: 'Greater',
        fields: [left,right],
        mode: [+,+],
        types: [any,any]
    }).
definition(
    like{
        name: 'Like',
        fields: [left,right,similarity],
        mode: [+,+,?],
        types: [string,string,float]
    }).
definition(
    concat{
        name: 'Concatenate',
        fields: [list,result],
        mode: [+,?],
        types: [list(string),string]
    }).
definition(
    trim{
        name: 'Trim',
        fields: [untrimmed,trimmed],
        mode: [+,?],
        types: [string,string]
    }).
definition(
    pad{
        name: 'Pad',
        fields: [string,char,times,result],
        mode: [+,+,+,?],
        types: [string,string,integer,string]
    }).
definition(
    sub_string{
        name: 'Substring',
        fields: [string,before,length,after,substring],
        mode: [+,?,?,?,?],
        types: [string,integer,integer,integer,string]
    }).
definition(
    re{
        name: 'Regexp',
        fields: [pattern,string,result],
        mode: [+,+,?],
        types: [string,string,list(string)]
    }).
definition(
    split{
        name: 'Split',
        fields: [string,pattern,list],
        mode: [+,+,?],
        types: [string,string,list(string)]
    }).
definition(
    upper{
        name: 'Upper',
        fields: [mixed,upper],
        mode: [+,?],
        types: [string,string]
    }).
definition(
    lower{
        name: 'Lower',
        fields: [mixed,lower],
        mode: [+,?],
        types: [string,string]
    }).
definition(
    is{
        name: 'Eval',
        fields: [expression,result],
        mode: [+,?],
        types: [arithmetic,decimal]
    }).
definition(
    dot{
        name: 'Dot',
        fields: [document,field,value],
        mode: [+,+,?],
        types: [json,string,data_value]
    }).
definition(
    length{
        name: 'Length',
        fields: [list,length],
        mode: [+,+,?],
        types: [list(any),integer]
    }).
definition(
    member{
        name: 'Member',
        fields: [member,list],
        mode: [?,+],
        types: [any,list(any)]
    }).
definition(
    join{
        name: 'Join',
        fields: [list, separator, result],
        mode: [+,+,?],
        types: [list(any),string,string]
    }).
definition(
    sum{
        name: 'Sum',
        fields: [list, result],
        mode: [+,?],
        types: [list(any),decimal]
    }).
definition(
    timestamp_now{
        name: 'Now',
        fields: [result],
        mode: [-],
        types: [decimal]
    }).



/* types */
definition(
    isa{
        name: 'IsA',
        fields: [element,type],
        mode: [?,?],
        types: [node,node]
    }).
definition(
    <<{
        name: 'Subsumption',
        fields: [child,parent],
        mode: [?,?],
        types: [node,node]
    }).
definition(
    typecast{
        name: 'Typecast',
        fields: [value,type,result],
        mode:  [+,+,?],
        types: [value,node,value]
    }).
definition(
    typeof{
        name: 'TypeOf',
        fields: [value,type],
        mode: [+,?],
        types: [value,node]
    }).
definition(
    true{
        name: 'True',
        fields: [],
        mode: [],
        types: []
    }).
definition(
    false{
        name: 'False',
        fields: [],
        mode: [],
        types: []
    }).

mode(Term, Mode) :-
    Term =.. [Head|Args],
    length(Args, N),
    Dict = Head{name:_,fields:_,mode:Mode_Candidate,types:_},
    definition(Dict),
    length(Mode, N),
    append(Mode, _, Mode_Candidate).

term_mode(Term, Mode) :-
    Term =.. [_|Args],
    maplist([Arg, ArgMode]>>(
                (   is_var(Arg)
                ->  ArgMode = ?
                ;   ArgMode = +)
            ),
            Args,
            Mode).

mode_element_subsumes(+,+).
mode_element_subsumes(+,?).
mode_element_subsumes(?,?).
mode_element_subsumes(-,?).
mode_element_subsumes(-,-).

mode_subsumes([],[]).
mode_subsumes([Mode1|Modes1],[Mode2|Modes2]) :-
    mode_element_subsumes(Mode1,Mode2),
    mode_subsumes(Modes1,Modes2).

operator(_=_).
operator(_>_).
operator(_<_).
operator(like(_,_,_)).
operator(concat(_,_)).
operator(trim(_,_)).
operator(pad(_,_,_,_)).
operator(sub_string(_,_,_,_,_)).
operator(re(_,_,_)).
operator(split(_,_,_)).
operator(upper(_,_)).
operator(lower(_,_)).
operator(_ is _).
operator(dot(_,_,_)).
operator(length(_,_,_)).
operator(join(_,_,_)).
operator(timestamp_now(_)).

cost(Term, Cost),
term_mode(Term, Term_Mode),
mode(Term, Mode),
\+ mode_subsumes(Term_Mode, Mode) =>
    Cost = inf.

cost((X,Y), Cost) =>
    cost(X, Cost_X),
    cost(Y, Cost_Y),
    Cost is Cost_X + Cost_Y.

cost((X;Y), Cost) =>
    cost(X, Cost_X),
    cost(Y, Cost_Y),
    Cost is Cost_X * Cost_Y.

cost(immediately(Query), Cost) =>
    cost(Query, Cost).

cost(opt(Query), Cost) =>
    cost(Query, Cost).

cost(once(_Query), Cost) =>
    Cost = 1.

cost(select(_Vars,Query), Cost) =>
    cost(Query, Cost).

cost(start(N,Query), Cost) =>
    cost(Query, Cost_Query),
    Cost is max(1.0, Cost_Query - N / Cost_Query).

cost(limit(N,Query), Cost) =>
    cost(Query, Cost_Query),
    Cost is max(1.0, Cost_Query - N / Cost_Query).

cost(count(Query,_), Cost) =>
    cost(Query, Cost).

cost(order_by(_,Query), Cost) =>
    cost(Query, Cost).

cost(opt(Query), Cost) =>
    cost(Query, Cost).

cost(not(Query), Cost) =>
    cost(Query, Cost).

cost(group_by(Query), Cost) =>
    cost(Query, Cost).

cost(distinct(Query), Cost) =>
    cost(Query, Cost).

cost(using(_,Query), Cost) =>
    cost(Query, Cost).

cost(from(_,Query), Cost) =>
    cost(Query, Cost).

cost(into(_,Query), Cost) =>
    cost(Query, Cost).

cost(get_document(_,_), Cost) =>
    Cost = 10.

cost(insert_document(_), Cost) =>
    Cost = 15.

cost(insert_document(_,_), Cost) =>
    Cost = 15.

cost(replace_document(_), Cost) =>
    Cost = 20.

cost(replace_document(_,_), Cost) =>
    Cost = 20.

cost(delete_document(_), Cost) =>
    Cost = 15.

cost(t(X, Y, Z), Cost),
non_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 1.

cost(t(X, Y, Z, _), Cost),
non_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 1.

cost(t(X, Y, Z), Cost),
is_var(X),
non_var(Y),
non_var(Z),
Y = rdf:type =>
    Cost = 100.

cost(t(X, Y, Z, _), Cost),
is_var(X),
non_var(Y),
non_var(Z),
Y = rdf:type =>
    Cost = 100.

cost(t(X, Y, Z), Cost),
is_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 5.

cost(t(X, Y, Z, _), Cost),
is_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 5.

cost(t(X, Y, Z), Cost),
non_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 3.

cost(t(X, Y, Z, _), Cost),
non_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 3.

cost(t(X, Y, Z), Cost),
non_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 2.

cost(t(X, Y, Z, _), Cost),
non_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 2.

cost(t(X, Y, Z), Cost),
non_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 6.

cost(t(X, Y, Z, _), Cost),
non_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 6.

cost(t(X, Y, Z), Cost),
is_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 15.

cost(t(X, Y, Z, _), Cost),
is_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 15.

cost(t(X, Y, Z), Cost),
is_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 10.

cost(t(X, Y, Z, _), Cost),
is_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 10.

cost(t(X, Y, Z), Cost),
is_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 30.

cost(t(X, Y, Z, _), Cost),
is_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 30.

/* addition */
cost(addition(X, Y, Z), Cost),
non_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 1.

cost(addition(X, Y, Z, _), Cost),
non_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 1.

cost(addition(X, Y, Z), Cost),
is_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 3.

cost(addition(X, Y, Z, _), Cost),
is_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 3.

cost(addition(X, Y, Z), Cost),
non_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 4.

cost(addition(X, Y, Z, _), Cost),
non_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 4.

cost(addition(X, Y, Z), Cost),
non_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 2.

cost(addition(X, Y, Z, _), Cost),
non_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 2.

cost(addition(X, Y, Z), Cost),
non_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 8.

cost(addition(X, Y, Z, _), Cost),
non_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 8.

cost(addition(X, Y, Z), Cost),
is_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 12.

cost(addition(X, Y, Z, _), Cost),
is_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 12.

cost(addition(X, Y, Z), Cost),
is_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 6.

cost(addition(X, Y, Z, _), Cost),
is_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 6.

cost(addition(X, Y, Z), Cost),
is_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 24.

cost(addition(X, Y, Z, _), Cost),
is_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 24.

cost(removal(X, Y, Z), Cost),
non_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 1.

cost(removal(X, Y, Z, _), Cost),
non_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 1.

cost(removal(X, Y, Z), Cost),
is_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 3.

cost(removal(X, Y, Z, _), Cost),
is_var(X),
non_var(Y),
non_var(Z) =>
    Cost = 3.

cost(removal(X, Y, Z), Cost),
non_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 4.

cost(removal(X, Y, Z, _), Cost),
non_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 4.

cost(removal(X, Y, Z), Cost),
non_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 2.

cost(removal(X, Y, Z, _), Cost),
non_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 2.

cost(removal(X, Y, Z), Cost),
non_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 8.

cost(removal(X, Y, Z, _), Cost),
non_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 8.

cost(removal(X, Y, Z), Cost),
is_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 12.

cost(removal(X, Y, Z, _), Cost),
is_var(X),
non_var(Y),
is_var(Z) =>
    Cost = 12.

cost(removal(X, Y, Z), Cost),
is_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 6.

cost(removal(X, Y, Z, _), Cost),
is_var(X),
is_var(Y),
non_var(Z) =>
    Cost = 6.

cost(removal(X, Y, Z), Cost),
is_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 24.

cost(removal(X, Y, Z, _), Cost),
is_var(X),
is_var(Y),
is_var(Z) =>
    Cost = 24.

cost(delete(_,_,_), Cost) =>
    Cost = 5.

cost(delete(_,_,_,_), Cost) =>
    Cost = 5.

cost(insert(_,_,_), Cost) =>
    Cost = 5.

cost(insert(_,_,_,_), Cost) =>
    Cost = 5.

cost(path(X, _, Y), Cost),
is_var(X),
non_var(Y) =>
    Cost = 15.

cost(path(X, _, Y), Cost),
non_var(X),
is_var(Y) =>
    Cost = 15.

cost(path(X, _, Y, _), Cost),
non_var(X),
is_var(Y) =>
    Cost = 25.

cost(path(X, _, Y), Cost),
is_var(X),
is_var(Y) =>
    Cost = 225.

cost(path(X, _, Y, _), Cost),
non_var(X),
is_var(Y) =>
    Cost = 625.

cost(path(X, _, Y, _), Cost),
non_var(X),
is_var(Y) =>
    Cost = 625.

cost(sum(_,_), Cost) =>
    Cost = 10.

cost(member(_,_), Cost) =>
    Cost = 10.

cost(Term, Cost),
operator(Term) =>
    Cost = 1.

cost(isa(X,Y), Cost),
non_var(X),
non_var(Y) =>
    Cost = 1.

cost(isa(X,Y), Cost),
is_var(X),
non_var(Y) =>
    Cost = 100.

cost(isa(X,Y), Cost),
non_var(X),
is_var(Y) =>
    Cost = 2.

cost(isa(X,Y), Cost),
is_var(X),
is_var(Y) =>
    Cost = 200.

cost(X << Y, Cost),
non_var(X),
non_var(Y) =>
    Cost = 1.

cost(X << Y, Cost),
is_var(X),
non_var(Y) =>
    Cost = 10.

cost(X << Y, Cost),
non_var(X),
is_var(Y) =>
    Cost = 10.

cost(X << Y, Cost),
is_var(X),
is_var(Y) =>
    Cost = 100.

cost(typecast(_,_,_), Cost) =>
    Cost = 1.

cost(typeof(_,_), Cost) =>
    Cost = 1.

cost(true, Cost) =>
    Cost = 0.

cost(false, Cost) =>
    Cost = 0.
