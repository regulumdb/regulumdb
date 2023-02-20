:- module(constraints,
          [
              run/3,
              run/4,
              run_report/3,
              check_constraint_document/3
          ]).

:- use_module(core(util)).
:- use_module(core(query)).
:- use_module(core(triple)).
:- use_module(core(transaction)).
:- use_module(core(document)).

/*

Term language for constraints
—————————————————————————————
Op ∈ Literal comparitors
V ∈ Literal Values
L,M,N ∈ Literal Variables
O ∈ Literal or Variable value := L | V
G ∈ Node
X,Y,Z ∈ Node Variables
W ∈ Node or Variable value := X | G
S,T ∈ Types
P,Q,R ∈ Field names
C,D,E ∈ Constraint := op(Op,X,O)
                     | t(X,P,Y)
                     | and(C,D)
                     | or(C,D)
                     | not(C) % not implemented yet
                     | impl(C,D)
                     | isa(X,T)


The term representing the "MidLifeInsurance" constraint is:

impl(and(isa(X,'Policy'),
         t(X,insurance_product,Y),
         isa(Y,'MidLifeInsurance')),
     and(t(X,customer,C),
         t(C,age,Z),
         Z < 70,
         Z > 35))

For each term, we also have its one hole contexts, which allows us to
do clause selection, and to have a partially completed context.

*/

negate(true,false).
negate(false,true).

inverse_op(<,>=).
inverse_op(>,<=).
inverse_op(>=,<).
inverse_op(=<,>).

select_redex(or(A,B),Remaining,Stack,Selected,Polarity) =>
    negate(Polarity,Negated),
    select_redex(A,[or1(B)|Remaining], Stack, Selected, Negated).
select_redex(and(A,B),Remaining,Stack,Selected,Polarity) =>
    select_redex(A,[and1(B)|Remaining], Stack, Selected, Polarity).
select_redex(impl(Ante,Con), Remaining, Stack, Selected, Polarity) =>
    negate(Polarity,Negated),
    select_redex(Ante, [impl1(Con)|Remaining], Stack, Selected, Negated).
select_redex(t(X,E,Y), Remaining, Stack, Selected, Polarity) =>
    Selected = t(X,E,Y)-Polarity,
    Stack = Remaining.
select_redex(op(Op,X,Y), Remaining, Stack, Selected, Polarity) =>
    Selected = op(Op,X,Y)-Polarity,
    Stack = Remaining.
select_redex(isa(X,T), Remaining, Stack, Selected, Polarity) =>
    Selected = isa(X,T)-Polarity,
    Stack = Remaining.
select_redex(true, Remaining, Stack, Selected, Polarity) =>
    Selected = true-Polarity,
    Stack = Remaining.

% plug the one hole context, and find the next Clause and Stack
step([and1(B)|T], Result, Next_Stack, Next_Clause, Polarity) :-
    select_redex(B,[and2(Result)|T], Next_Stack, Next_Clause, Polarity).
step([and2(A)|T], Result, Next_Stack, Next_Clause, Polarity) :-
    step(T, and(A,Result), Next_Stack, Next_Clause, Polarity).
step([or1(B)|T], Result, Next_Stack, Next_Clause, Polarity) :-
    (   step(T, or(Result,B), Next_Stack, Next_Clause, Polarity)
    *-> true
    ;   negate(Polarity,Negated),
        select_redex(B, [or2(Result)|T], Next_Stack, Next_Clause, Negated)
    ).
step([and2(A)|T], Result, Next_Stack, Next_Clause, Polarity) :-
    step(T, and(A,Result), Next_Stack, Next_Clause, Polarity).
step([impl1(Consequent)|T], Result, Next_Stack, Next_Clause, Polarity) :-
    negate(Polarity,Negated),
    select_redex(Consequent,[impl2(Result)|T], Next_Stack, Next_Clause, Negated).
step([impl2(Antecedent)|T], Result, Next_Stack, Next_Clause, Polarity) :-
    step(T, impl(Antecedent, Result), Next_Stack, Next_Clause, Polarity).

run(Db, Constraint, Failed_At) :-
    select_redex(Constraint, [], Remaining, Clause, true),
    run(Clause, Remaining, Db, Failed_At).

raw(X^^_, X) :-
    !.
raw(X,X).

run_clause(true, _Db).
run_clause(t(X,P,Y), Db) :-
    database_prefixes(Db, Prefixes),
    prefix_expand_schema(P, Prefixes, PEx),
    database_instance(Db, G),
    xrdf(G,X,PEx,Y).
run_clause(op(Op,X,Y), _) :-
    raw(X,XRaw),
    raw(Y,YRaw),
    call(Op,XRaw,YRaw).
run_clause(isa(X,T), Db) :-
    database_prefixes(Db, Prefixes),
    prefix_expand_schema(T, Prefixes, TEx),
    global_prefix_expand(rdf:type, RDF_Type),
    run_clause(t(X,RDF_Type,TEx),Db).

run(Clause-false, Remaining, Db, Failed_At) :-
    (   run_clause(Clause, Db)
    *-> step(Remaining,Clause,Next_Stack, Next_Clause, false),
        run(Next_Clause, Next_Stack, Db, Failed_At)
    ;   step(Remaining,Clause,Next_Stack, Next_Clause, false),
        run(Next_Clause, Next_Stack, Db, Failed_At)
    ).
run(Clause-true, Remaining, Db, failed_at(Clause,Remaining)) :-
    \+ run_clause(Clause, Db).
run(Clause-true, Remaining, Db, Failed_At) :-
    run_clause(Clause, Db),
    step(Remaining,Clause,Next_Stack,Next_Clause, true),
    run(Next_Clause, Next_Stack, Db, Failed_At).

context_hole_term([],Term,Term).
context_hole_term([and1(B)|T],A,Term) :-
    context_hole_term(T,and(A,B),Term).
context_hole_term([and2(A)|T],B,Term) :-
    context_hole_term(T,and(A,B),Term).
context_hole_term([or1(B)|T],A,Term) :-
    context_hole_term(T,or(A,B),Term).
context_hole_term([or2(A)|T],B,Term) :-
    context_hole_term(T,or(A,B),Term).
context_hole_term([impl2(A)|T],B,Term) :-
    context_hole_term(T,impl(A,B),Term).

failure_report(Db, failed_at(Clause,Remaining),Report) :-
    database_prefixes(Db, Prefixes),
    context_hole_term(Remaining,Clause,Term),
    !,
    render_constraint(Clause,Prefixes,Clause_String),
    render_constraint(Term,Prefixes,Term_String),
    format(string(Report),"Failed to satisfy: ~w~n~n    In the Constraint:~n~n~w~n",
           [Clause_String, Term_String]).

run_report(Db, Constraint, Report) :-
    (   run(Db, Constraint, Failed_At)
    ->  failure_report(Db, Failed_At, Report)
    ).

% Some folds here with or...  Let's think about it in a minute
/*
step([or(Before,[Next_Constraint|After])|T], Result, Next_Stack, Next_Clause) :-
    select_redex(Next_Constraint,[or([Result|Before],After)|T], Next_Stack, Next_Clause).
*/

render_constraint(Constraint,Prefixes,String) :-
    render_constraint(Constraint,Prefixes,String, 0).

render_constraint(isa(X,T), Prefixes, String, Indent) :-
    'document/json':compress_dict_uri(X,Prefixes,XPretty),
    pad('',' ',Indent,Pad),
    format(string(String), "~q:~q~n~s", [XPretty,T,Pad]).
render_constraint(op(Op,B,C), _, String, Indent) :-
    raw(B,BRaw),
    raw(C,CRaw),
    pad('',' ',Indent,Pad),
    format(string(String),
           "~q ~s ~q~n~s", [BRaw,Op,CRaw,Pad]).
render_constraint(t(A,B,C), Prefixes, String, Indent) :-
    'document/json':compress_dict_uri(A,Prefixes,APretty),
    'document/json':compress_schema_uri(B,Prefixes,BPretty),
    (   atom(C)
    ->  'document/json':compress_dict_uri(C, Prefixes, CPretty)
    ;   raw(C, CPretty)
    ),
    pad('',' ',Indent,Pad),
    format(string(String),
           "~q =[~q]> ~q~n~s", [APretty,BPretty,CPretty,Pad]).
render_constraint(or(A,B), Prefixes, String, Indent) :-
    render_constraint(A, Prefixes, StringA, Indent),
    render_constraint(B, Prefixes, StringB, Indent),
    format(string(String),
           "(~s) ∨ (~s)", [StringA,StringB]).
render_constraint(and(A,B), Prefixes, String, Indent) :-
    render_constraint(A, Prefixes, StringA, Indent),
    render_constraint(B, Prefixes, StringB, Indent),
    format(string(String),
           "~s ∧ ~s", [StringA,StringB]).
render_constraint(impl(A,B), Prefixes, String, Indent) :-
    Indent_First is Indent + 2,
    render_constraint(A, Prefixes, StringA, Indent_First),
    Indent_Next is Indent + 4,
    render_constraint(B, Prefixes, StringB, Indent_Next),
    pad('',' ',Indent_Next,Pad),
    format(string(String),
           "( ~s ) ⇒~n~s~s", [StringA,Pad,StringB]).

term_conjunction(Terms, Conj) :-
    (   Terms = []
    ->  Conj = false
    ;   Terms = [Conj]
    ->  true
    ;   Terms = [Term0|Rest],
        foldl([Term1, Term2, and(Term2,Term1)]>>true, Rest, Term0, Conj)
    ).

term_disjunction(Terms, Disj) :-
    (   Terms = []
    ->  Disj = true
    ;   Terms = [Disj]
    ->  true
    ;   Terms = [Term0|Rest],
        foldl([Term1, Term2, or(Term2,Term1)]>>true, Rest, Term0, Disj)
    ).

% performs a binding fold.
merge_bindings([Bindings], Bindings).
merge_bindings([Bindings0|Bindings_List], Bindings) :-
    merge_bindings(Bindings_List, Bindings0, Bindings).

merge_bindings([], Bindings, Bindings).
merge_bindings([BindingsNext|Bindings_List], Bindings0, Bindings) :-
    dict_pairs(BindingsNext,bindings,Pairs),
    foldl([Key-Value,Bindings_In,Bindings_Out]>>
          (   get_dict(Key,Bindings_In,Value)
          ->  Bindings_In = Bindings_Out
          ;   put_dict(Key,Bindings_In,Value,Bindings_Out)
          ),
          Pairs,Bindings0,Bindings_Middle),
    merge_bindings(Bindings_List,Bindings_Middle,Bindings).

:- begin_tests(merge_bindings).

test(merge_vars_for_or, []) :-
    D1 = bindings{
             var1: _X,
             var2: _Y
         },
    D2 = bindings{
             var2: _Z,
             var3: _W
         },

    merge_bindings([D1,D2], D3),

    get_dict(var1,D1,Var11),
    get_dict(var1,D3,Var13),
    Var11 == Var13,
    get_dict(var2,D1,Var21),
    get_dict(var2,D2,Var22),
    get_dict(var2,D2,Var23),
    Var21 == Var22, Var22 == Var23,
    get_dict(var3,D2,Var32),
    get_dict(var3,D3,Var33),
    Var32 == Var33.

:- end_tests(merge_bindings).

pair_rule('@var'-Var, Subject, true, Bindings_In, Bindings_Out) =>
    atom_string(VarAtom,Var),
    put_dict(VarAtom, Bindings_In, Subject, Bindings_Out).
pair_rule('@or'-List, Subject, Term, Bindings_In, Bindings_Out) =>
    maplist({Bindings_In,Subject}/[Constraint,Term0,Bindings_Out]>>
            compile_constraint_rule(Constraint,Subject,Term0,Bindings_In,Bindings_Out),
            List,
            Terms,
            Bindings_List),
    merge_bindings(Bindings_List, Bindings_Out),
    term_disjunction(Terms,Term).
pair_rule('@and'-List, Subject, Term, Bindings_In, Bindings_Out) =>
    mapm({Subject}/[Constraint,Term0,Bindings_In0,Bindings_Out0]>>
         compile_constraint_rule(Constraint,Subject,Term0,Bindings_In0,Bindings_Out0),
         List,
         Terms,
         Bindings_In,
         Bindings_Out),
    term_conjunction(Terms,Term).
pair_rule('@gt'-Value, Subject, Term, Bindings_In, Bindings_Out) =>
    Term = op(>,Subject,Value),
    Bindings_In = Bindings_Out.
pair_rule('@lt'-Value, Subject, Term, Bindings_In, Bindings_Out) =>
    Term = op(<,Subject,Value),
    Bindings_In = Bindings_Out.
pair_rule('@ge'-Value, Subject, Term, Bindings_In, Bindings_Out) =>
    Term = op(>=,Subject,Value),
    Bindings_In = Bindings_Out.
pair_rule('@le'-Value, Subject, Term, Bindings_In, Bindings_Out) =>
    Term = op(=<,Subject,Value),
    Bindings_In = Bindings_Out.
pair_rule('@eq'-Value, Subject, Term, Bindings_In, Bindings_Out) =>
    Term = op(=,Subject,Value),
    Bindings_In = Bindings_Out.
pair_rule('@ne'-Value, Subject, Term, Bindings_In, Bindings_Out) =>
    Term = op(\=,Subject,Value),
    Bindings_In = Bindings_Out.
pair_rule('@isa'-Value, Subject, Term, Bindings_In, Bindings_Out) =>
    atom_string(Atom,Value),
    Term = isa(Subject,Atom),
    Bindings_In = Bindings_Out.
pair_rule(Field-Value, Subject, Term, Bindings_In, Bindings_Out) =>
    T1 = t(Subject,Field,Object),
    compile_constraint_rule(Value, Object, T2, Bindings_In, Bindings_Out),
    Term = and(T1,T2).

% I'm just going to make implication special, otherwise it's annoying.
compile_constraint_rule(Dictionary, Subject, Term, Bindings_In, Bindings_Out),
is_dict(Dictionary),
get_dict('@when', Dictionary, Ante) =>
    get_dict('@then', Dictionary, Con),
    compile_constraint_rule(Ante, Subject, Term1, Bindings_In, Bindings_Middle),
    compile_constraint_rule(Con, Subject, Term2, Bindings_Middle, Bindings_Out),
    Term = impl(Term1,Term2).
compile_constraint_rule(Dictionary, Subject, Term, Bindings_In, Bindings_Out),
is_dict(Dictionary) =>
    dict_pairs(Dictionary, _, Pairs),
    mapm({Subject}/[Pair,Rule,BI,BO]>>pair_rule(Pair,Subject,Rule,BI,BO),
         Pairs, Rules, Bindings_In, Bindings_Out),
    term_conjunction(Rules,Term).

compile_constraint(Document, Constraint) :-
    get_dict('@rules', Document, Rules),
    Bindings = bindings{},
    maplist({Bindings,Subject}/[Rule,Term]>>compile_constraint_rule(Rule, Subject, Term, _{}, _),
            Rules, Terms),
    term_conjunction(Terms, Constraint).

check_constraint_document(_,_,_) :-
    fail.

:- begin_tests(constraints).

:- use_module(core(util/test_utils)).

test(or_test1, [fail]) :-
    % Success is failure
    Or_Test = or(op(>,10,12),
                 op(<,10,12)),
    run(fake_db, Or_Test, _Failed_At).

test(or_test2, []) :-
    Or_Test = or(op(>,10,100),
                 op(>,10,30)),
    run(fake_db, Or_Test, Failed_At),
    !,
    Failed_At = failed_at(Op,Ctx),
    Op = op(>,10,30),
    Ctx = [or2(op(>,10,100))],

    context_hole_term(Ctx, Op, Term),
    !,
    Term = or(op(>,10,100),op(>,10,30)).

insurance_schema('
{ "@type" : "@context",
  "@base" : "iri://insurance/",
  "@schema" : "iri://insurance#",
  "@metadata" :
  { "constraints" : [
      { "@name" : "MidLifeInsurance",
        "@rules" : [{ "@when" : { "@isa" : "Policy",
                                  "insurance_product" : { "@isa" : "MidLifeInsurance" }},
                      "@then" : { "customer" : { "age" : { "@and" : [{ "@gt" : 30 },
                                                                     { "@lt" : 60 }]}}}}]
      }
    ]
  }
}
{ "@type" : "Class",
  "@id" : "Customer",
  "@key" : { "@type" : "Lexical", "@fields" : ["forename", "surname", "id"]},
  "forename" : "xsd:string",
  "surname" : "xsd:string",
  "id" : "xsd:long",
  "age" : "xsd:nonNegativeInteger"
}
{ "@type" : "Class",
  "@id" : "InsuranceProduct",
  "@abstract" : [],
  "name" : "xsd:string"
}
{ "@type" : "Class",
  "@id" : "MidLifeInsurance",
  "@inherits" : "InsuranceProduct",
  "@key" : { "@type" : "Lexical", "@fields" : ["name"]}
}
{ "@type" : "Class",
  "@id" : "Policy",
  "@key" : { "@type" : "Lexical", "@fields" : ["id"]},
  "id" : "xsd:long",
  "customer" : "Customer",
  "insurance_product" : "InsuranceProduct",
  "start_date" : "xsd:dateTime",
  "end_date" : "xsd:dateTime"
}
').

insurance_database(
    [
        json{ '@type' : "MidLifeInsurance",
              '@capture' : "Product/midlife",
              name : "Mid-Life Insurance Product" },
        json{ '@type' : "Customer",
              '@capture' : "Customer/jim",
              forename : "Jim",
              surname : "McCoy",
              id : 1,
              age : 40
            },
        json{ '@type' : "Customer",
              '@capture' : "Customer/jill",
              forename : "Jill",
              surname : "Curry",
              id : 2,
              age : 12
            },
        json{ '@type' : "Policy",
              id : 1,
              insurance_product : json{ '@ref' : "Product/midlife" },
              customer : json{ '@ref' : "Customer/jim" },
              start_date : "2020-01-01T00:00:00Z",
              end_date : "2050-01-01T00:00:00Z"
            },
        json{ '@type' : "Policy",
              id : 2,
              insurance_product : json{ '@ref' : "Product/midlife" },
              customer : json{ '@ref' : "Customer/jim" },
              start_date : "2030-01-01T00:00:00Z",
              end_date : "2060-01-01T00:00:00Z"
            },
        json{ '@type' : "Policy",
              id : 3,
              insurance_product : json{ '@ref' : "Product/midlife" },
              customer : json{ '@ref' : "Customer/jill" },
              start_date : "2030-01-01T00:00:00Z",
              end_date : "2060-01-01T00:00:00Z"
            }
    ]
).

:- use_module(core(api)).

insert_insurance_documents(Desc) :-
    insurance_database(Documents),

    with_test_transaction(
        Desc,
        C1,
        (   empty_assoc(Captures_In),
            api_document:api_insert_document_from_lazy_list(
                Documents, instance, false, C1, Captures_In, _Captures_Out,
                _Backlinks, _Ids))
    ).

test(or_impl_test,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(insurance_schema, Desc))),
      cleanup(teardown_temp_store(State))
     ]
    ) :-

    insert_insurance_documents(Desc),

    open_descriptor(Desc, Db),

    Or_Impl = impl(isa(Customer, 'Customer'),
                   and(t(Customer, age, Age),
                       or(op(>, Age, 30),
                          op(<, Age, 10)))),
    run(Db, Or_Impl, Failed_At),
    !,
    Failed_At = failed_at(Op, Ctx),
    Op = op(<,12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger',10),
    Ctx =  [ or2(op(>,
					12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger',
					30)),
			 and2(t('iri://insurance/Customer/Jill+Curry+2',
					age,
					12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger')),
			 impl2(isa('iri://insurance/Customer/Jill+Curry+2',
					   'Customer'))
		   ],

    context_hole_term(Ctx,Op,Term),
    !,
    Term = impl(isa('iri://insurance/Customer/Jill+Curry+2',
					'Customer'),
				and(t('iri://insurance/Customer/Jill+Curry+2',
					  age,
					  12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger'),
					or(op(>,
						  12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger',
						  30),
					   op(<,
						  12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger',
						  10)))),

    failure_report(Db, Failed_At, String),
    String = "Failed to satisfy: 12 < 10\n\n\n    In the Constraint:\n\n( 'Customer/Jill+Curry+2':'Customer'\n   ) ⇒\n    'Customer/Jill+Curry+2' =[age]> 12\n     ∧ (12 > 30\n    ) ∨ (12 < 10\n    )\n".

test(midlife_insurance,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(insurance_schema, Desc))),
      cleanup(teardown_temp_store(State))
     ]
    ) :-

    insert_insurance_documents(Desc),

    MidLife = impl(and(isa(Policy,'Policy'),
                       and(t(Policy,insurance_product,Product),
                           isa(Product,'MidLifeInsurance'))),
                   and(t(Policy,customer,Customer),
                       and(t(Customer,age,Age),
                           and(op(<,Age,70),
                               op(>,Age,35))))),

    open_descriptor(Desc, Db),
    run(Db, MidLife, Failed_At),
    !,
    Failed_At = failed_at(Op, Ctx),
    Op = op(>,
			12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger',
			35),

    Ctx = [ and2(op(<,
					12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger',
					70)),
			and2(t('iri://insurance/Customer/Jill+Curry+2',
				   age,
				   12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger')),
			and2(t(A,customer,'iri://insurance/Customer/Jill+Curry+2')),
			impl2(and(isa(A,'Policy'),
					  and(t(A,insurance_product,
							'iri://insurance/MidLifeInsurance/Mid-Life%20Insurance%20Product'),
						  isa('iri://insurance/MidLifeInsurance/Mid-Life%20Insurance%20Product',
							  'MidLifeInsurance'))))
		  ],
    !,
    context_hole_term(Ctx,Op,Term),

    Term = impl(and(isa('iri://insurance/Policy/3','Policy'),
					and(t('iri://insurance/Policy/3',
						  insurance_product,
						  'iri://insurance/MidLifeInsurance/Mid-Life%20Insurance%20Product'),
						isa('iri://insurance/MidLifeInsurance/Mid-Life%20Insurance%20Product',
							'MidLifeInsurance'))),
				and(t('iri://insurance/Policy/3',
					  customer,
					  'iri://insurance/Customer/Jill+Curry+2'),
					and(t('iri://insurance/Customer/Jill+Curry+2',
						  age,
						  12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger'),
						and(op(<,
							   12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger',
							   70),
							op(>,
							   12 ^^ 'http://www.w3.org/2001/XMLSchema#nonNegativeInteger',
							   35))))),

    failure_report(Db, Failed_At, String),

    String = "Failed to satisfy: 12 > 35\n\n\n    In the Constraint:\n\n( 'Policy/3':'Policy'\n   ∧ 'Policy/3' =[insurance_product]> 'MidLifeInsurance/Mid-Life%20Insurance%20Product'\n   ∧ 'MidLifeInsurance/Mid-Life%20Insurance%20Product':'MidLifeInsurance'\n   ) ⇒\n    'Policy/3' =[customer]> 'Customer/Jill+Curry+2'\n     ∧ 'Customer/Jill+Curry+2' =[age]> 12\n     ∧ 12 < 70\n     ∧ 12 > 35\n    \n".


test(compile_constraint,
     [setup((setup_temp_store(State),
             test_document_label_descriptor(Desc),
             write_schema(insurance_schema, Desc))),
      cleanup(teardown_temp_store(State))
     ]) :-
    database_context_object(Desc, Context),
    Constraints = (Context.'@metadata'.constraints),
    [Constraint1|_Constraints_Rest] = Constraints,
    compile_constraint(Constraint1, Term),

    Term = impl(and(isa(P0,'Policy'),
                    and(t(P1,insurance_product,PR1),
                        isa(PR2,'MidLifeInsurance'))),
                and(t(P2,customer,C1),
                    and(t(C2,age,A1),
                        and(op(>,A2,30),
                            op(<,A3,60))))),

    P0 == P1, P1 == P2,
    PR1 == PR2,
    C1 == C2,
    A1 == A2, A2 == A3.

test(insurance_no_overlap, [blocked('not written yet')]) :-
/*
Example constraint2:

Example constraint:

{ "@type": "Constraint",
  "@id": "InsuranceNoOverlap",
  "@doc": "People with an insurance policy can't have that same product in an overlapping duration",
  "@on": "Policy",
  "@constraints": [{"@id": {"@var": "policy_id"}},
                   {"@not": [{"insurance_product": {"@type": {"@var": "product_type_1"}}},
                             {"customer": {"@linked-by": {"@type": "Policy", "@property": "customer},
                                           "@id": {"@var": "policy_id_2"}}},
                             {"@ne": [{"@var": "policy_id"},
                                      {"@var": "policy_id_2"}]},
                             {"@match": {"@id": {"@var": "policy_id_2"},
                                         "insurance_product": {"@var": "product_type_1"}}},
                             {"@match": {"@id": {"@var": "policy_id"},
                                         "start_date": {"@var": "policy_1_start_date"},
                                         "end_date": {"@var": "policy_1_start_date"}}},
                             {"@match": {"@id": {"@var": "policy_id_2"},
                                         "start_date": {"@var": "policy_2_start_date"},
                                         "end_date": {"@var": "policy_2_start_date"}}},
                             {"@or": [{"@between": {"@from": {"@var": "policy_1_start_date"},
                                                    "@to": {"@var": "policy_1_end_date"},
                                                    "@element: {"@var": "policy_2_start_date"}}},
                                      {"@between": {"@from": {"@var": "policy_1_start_date"},
                                                    "@to": {"@var": "policy_1_end_date"},
                                                    "@element: {"@var": "policy_2_end_date"}}}]}]}]
*/

    _No_Overlap = impl(and(isa(Policy1,'Policy'),
                          and(t(Policy1,insurance_product,Product),
                              and(t(Policy1,customer,Customer),
                                  and(t(Policy2,customer,Customer),
                                      and(op(\=,Policy1,Policy2),
                                          t(Policy2, insurance_product, Product)))))),
                      and(t(Policy1,start_date,Start_Date1),
                          and(t(Policy2,start_date,Start_Date2),
                              and(t(Policy1,end_date,End_Date1),
                                  and(t(Policy2, end_date, End_Date2),
                                      or(and(op(<,Start_Date1, End_Date2),
                                             op(<,End_Date2, End_Date1)),
                                         and(op(<,Start_Date1, Start_Date2),
                                             op(<,Start_Date2, End_Date1)))))))).

:- end_tests(constraints).
