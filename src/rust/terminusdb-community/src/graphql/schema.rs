use std::sync::Arc;

use juniper::meta::{DeprecationStatus, EnumValue, Field};
use juniper::{
    graphql_value, DefaultScalarValue, FromInputValue, GraphQLEnum, GraphQLType, GraphQLValue,
    InputValue, Registry, Value, ID,
};
use swipl::prelude::*;
use terminusdb_store_prolog::terminus_store::store::sync::SyncStoreLayer;
use terminusdb_store_prolog::terminus_store::{IdTriple, Layer};

use crate::consts::{RDF_FIRST, RDF_NIL, RDF_REST, RDF_TYPE, SYS_VALUE};
use crate::doc::{retrieve_all_index_ids, ArrayIterator, GetDocumentContext};
use crate::path::iterator::{CachedClonableIterator, ClonableIterator};
use crate::schema::RdfListIterator;
use crate::types::{transaction_instance_layer, transaction_schema_layer};
use crate::value::{
    enum_node_to_value, type_is_big_integer, type_is_bool, type_is_datetime, type_is_decimal,
    type_is_float, type_is_json, type_is_small_integer, value_to_graphql,
};

use super::filter::{FilterInputObject, FilterInputObjectTypeInfo};
use super::frame::*;
use super::query::run_filter_query;
use super::top::System;

#[derive(Clone)]
pub struct SystemInfo {
    pub user: Atom,
    pub system: SyncStoreLayer,
    pub commit: Option<SyncStoreLayer>,
    pub meta: Option<SyncStoreLayer>,
}

#[derive(Clone)]
pub struct TerminusContext<'a, C: QueryableContextType> {
    pub context: &'a Context<'a, C>,
    pub transaction_term: Term<'a>,
    pub system_info: SystemInfo,
    pub schema: SyncStoreLayer,
    pub instance: Option<SyncStoreLayer>,
}

impl<'a, C: QueryableContextType> TerminusContext<'a, C> {
    pub fn new(
        context: &'a Context<'a, C>,
        _auth_term: &Term,
        system_term: &Term,
        meta_term: &Term,
        commit_term: &Term,
        transaction_term: &Term,
    ) -> PrologResult<TerminusContext<'a, C>> {
        let user_: Atom = Atom::new("terminusdb://system/data/User/admin"); //auth_term.get_ex()?;
        let user = if user_ == atom!("anonymous") {
            atom!("terminusdb://system/data/User/anonymous")
        } else {
            user_
        };
        let system =
            transaction_instance_layer(context, system_term)?.expect("system layer not found");
        let meta = if meta_term.unify(atomable("none")).is_ok() {
            None
        } else {
            transaction_instance_layer(context, meta_term).expect("Missing meta layer")
        };
        let commit = if commit_term.unify(atomable("none")).is_ok() {
            None
        } else {
            transaction_instance_layer(context, commit_term).expect("Missing commit layer")
        };

        let schema =
            transaction_schema_layer(context, transaction_term)?.expect("missing schema layer");
        let instance = transaction_instance_layer(context, transaction_term)?;

        let new_transaction_term = context.new_term_ref();
        new_transaction_term.unify(&transaction_term)?;

        Ok(TerminusContext {
            system_info: SystemInfo {
                user,
                system,
                meta,
                commit,
            },
            transaction_term: new_transaction_term,
            context,
            schema,
            instance,
        })
    }
}

pub struct TerminusTypeCollection<'a, C: QueryableContextType> {
    _c: std::marker::PhantomData<&'a Context<'a, C>>,
}

impl<'a, C: QueryableContextType> TerminusTypeCollection<'a, C> {
    pub fn new() -> Self {
        Self {
            _c: Default::default(),
        }
    }
}

pub struct TerminusOrderingInfo {
    ordering_name: String,
    type_name: String,
    allframes: Arc<AllFrames>,
}

impl TerminusOrderingInfo {
    fn new(type_name: &str, allframes: &Arc<AllFrames>) -> Self {
        Self {
            ordering_name: format!("{}_Ordering", type_name),
            type_name: type_name.to_string(),
            allframes: allframes.clone(),
        }
    }
}

fn add_arguments<'r>(
    info: &TerminusTypeInfo,
    registry: &mut juniper::Registry<'r, DefaultScalarValue>,
    mut field: Field<'r, DefaultScalarValue>,
    class_definition: &ClassDefinition,
) -> Field<'r, DefaultScalarValue> {
    field = field.argument(registry.arg::<Option<ID>>("id", &()));
    field = field.argument(registry.arg::<Option<Vec<ID>>>("ids", &()));
    field = field.argument(
        registry
            .arg::<Option<i32>>("offset", &())
            .description("skip N elements"),
    );
    field = field.argument(
        registry
            .arg::<Option<i32>>("limit", &())
            .description("limit results to N elements"),
    );
    field = field.argument(registry.arg::<Option<FilterInputObject>>(
        "filter",
        &FilterInputObjectTypeInfo::new(&info.class, &info.allframes),
    ));
    if must_generate_ordering(class_definition) {
        field = field.argument(
            registry
                .arg::<Option<TerminusOrderBy>>(
                    "orderBy",
                    &TerminusOrderingInfo::new(&info.class, &info.allframes),
                )
                .description("order by the given fields"),
        );
    }

    field
}

fn must_generate_ordering(class_definition: &ClassDefinition) -> bool {
    for (_, field) in class_definition.fields.iter() {
        if field.base_type().is_some() {
            return true;
        }
    }

    false
}

pub fn is_reserved_field_name(name: &String) -> bool {
    name == "id"
}

impl<'a, C: QueryableContextType + 'a> GraphQLType for TerminusTypeCollection<'a, C> {
    fn name(_info: &Self::TypeInfo) -> Option<&str> {
        Some("Query")
    }

    fn meta<'r>(
        info: &Self::TypeInfo,
        registry: &mut juniper::Registry<'r, DefaultScalarValue>,
    ) -> juniper::meta::MetaType<'r, DefaultScalarValue>
    where
        DefaultScalarValue: 'r,
    {
        let mut fields: Vec<_> = info
            .allframes
            .frames
            .iter()
            .filter_map(|(name, typedef)| {
                if let TypeDefinition::Class(c) = typedef {
                    let newinfo = TerminusTypeInfo {
                        class: name.to_owned(),
                        allframes: info.allframes.clone(),
                    };
                    let field = registry.field::<Vec<TerminusType<'a, C>>>(name, &newinfo);

                    Some(add_arguments(&newinfo, registry, field, c))
                } else {
                    None
                }
            })
            .collect();
        let restriction_fields: Vec<_> = info
            .allframes
            .restrictions
            .iter()
            .map(|(name, restrictiondef)| {
                let newinfo = TerminusTypeInfo {
                    class: restrictiondef.on.to_owned(),
                    allframes: info.allframes.clone(),
                };
                let field = registry.field::<Vec<TerminusType<'a, C>>>(name, &newinfo);
                let class_def;
                if let TypeDefinition::Class(c) = info
                    .allframes
                    .frames
                    .get(&restrictiondef.on)
                    .expect("Restriction not on known class")
                {
                    class_def = c;
                } else {
                    panic!("Restriction not on a class");
                }

                add_arguments(&newinfo, registry, field, class_def)
            })
            .collect();

        fields.extend(restriction_fields);

        /*
        fields.push(registry.field::<System>("_system", &()));
        */
        registry
            .build_object_type::<TerminusTypeCollection<'a, C>>(info, &fields)
            .into_meta()
    }
}

#[derive(Clone)]
pub struct TerminusTypeCollectionInfo {
    pub allframes: Arc<AllFrames>,
}

fn result_to_execution_result<C: QueryableContextType, T>(
    context: &Context<C>,
    result: PrologResult<T>,
) -> Result<T, juniper::FieldError> {
    result_to_string_result(context, result).map_err(|e| match e {
        PrologStringError::Failure => juniper::FieldError::new("prolog call failed", Value::Null),
        PrologStringError::Exception(e) => juniper::FieldError::new(e, Value::Null),
    })
}

fn pl_ids_from_restriction<C: QueryableContextType>(
    context: &TerminusContext<C>,
    restriction: &RestrictionDefinition,
) -> PrologResult<Vec<u64>> {
    let mut result = Vec::new();
    let prolog_context = &context.context;
    let frame = prolog_context.open_frame();
    let [restriction_term, id_term, reason_term] = frame.new_term_refs();
    restriction_term.unify(restriction.original_id.as_ref().unwrap())?;
    let open_call = frame.open(
        pred!("query:ids_for_restriction/4"),
        [
            &context.transaction_term,
            &restriction_term,
            &id_term,
            &reason_term,
        ],
    );
    while attempt_opt(open_call.next_solution())?.is_some() {
        let id: u64 = id_term.get_ex()?;
        result.push(id);
    }

    Ok(result)
}

fn ids_from_restriction<C: QueryableContextType>(
    context: &TerminusContext<C>,
    restriction: &RestrictionDefinition,
) -> Result<Vec<u64>, juniper::FieldError> {
    let result = pl_ids_from_restriction(context, restriction).map(|mut r| {
        r.sort();
        r.dedup();

        r
    });
    result_to_execution_result(context.context, result)
}

fn pl_id_matches_restriction<'a, C: QueryableContextType>(
    context: &TerminusContext<'a, C>,
    restriction: &str,
    id: u64,
) -> PrologResult<Option<String>> {
    let prolog_context = &context.context;
    let frame = prolog_context.open_frame();
    let [restriction_term, id_term, reason_term] = frame.new_term_refs();
    restriction_term.unify(restriction)?;
    id_term.unify(id)?;
    let open_call = frame.open(
        pred!("query:ids_for_restriction/4"),
        [
            &context.transaction_term,
            &restriction_term,
            &id_term,
            &reason_term,
        ],
    );
    if attempt_opt(open_call.next_solution())?.is_some() {
        let reason: String = reason_term.get_ex()?;
        Ok(Some(reason))
    } else {
        Ok(None)
    }
}

pub fn id_matches_restriction<'a, C: QueryableContextType>(
    context: &TerminusContext<'a, C>,
    restriction: &str,
    id: u64,
) -> Result<Option<String>, juniper::FieldError> {
    let result = pl_id_matches_restriction(context, restriction, id);
    result_to_execution_result(&context.context, result)
}

impl<'a, C: QueryableContextType> GraphQLValue for TerminusTypeCollection<'a, C> {
    type Context = TerminusContext<'a, C>;

    type TypeInfo = TerminusTypeCollectionInfo;

    fn type_name<'i>(&self, _info: &'i Self::TypeInfo) -> Option<&'i str> {
        Some("TerminusTypeCollection")
    }

    fn resolve_field(
        &self,
        info: &Self::TypeInfo,
        field_name: &str,
        arguments: &juniper::Arguments<DefaultScalarValue>,
        executor: &juniper::Executor<Self::Context, DefaultScalarValue>,
    ) -> juniper::ExecutionResult<DefaultScalarValue> {
        if field_name == "_system" {
            executor.resolve_with_ctx(&(), &System {})
        } else {
            let zero_iter;
            let type_name;
            if let Some(restriction) = info.allframes.restrictions.get(field_name) {
                // This is a restriction. We're gonna have to call into prolog to get an iri list and turn it into an iterator over ids to use as a zero iter
                type_name = restriction.on.as_str();
                let id_list = ids_from_restriction(executor.context(), restriction)?;
                zero_iter = Some(ClonableIterator::new(id_list.into_iter()));
            } else {
                type_name = field_name;
                zero_iter = None;
            }
            let objects = match executor.context().instance.as_ref() {
                Some(instance) => run_filter_query(
                    executor.context(),
                    instance,
                    &info.allframes.context,
                    arguments,
                    type_name,
                    &info.allframes,
                    zero_iter,
                )
                .into_iter()
                .map(|id| TerminusType::new(id))
                .collect(),
                None => vec![],
            };

            executor.resolve(
                &TerminusTypeInfo {
                    class: type_name.to_owned(),
                    allframes: info.allframes.clone(),
                },
                &objects,
            )
        }
    }
}

pub struct TerminusTypeInfo {
    class: String,
    allframes: Arc<AllFrames>,
}

pub struct TerminusType<'a, C: QueryableContextType> {
    id: u64,
    _x: std::marker::PhantomData<Context<'a, C>>,
}

impl<'a, C: QueryableContextType + 'a> TerminusType<'a, C> {
    fn new(id: u64) -> Self {
        Self {
            id,
            _x: Default::default(),
        }
    }

    fn register_field<'r, T: GraphQLType>(
        registry: &mut Registry<'r, DefaultScalarValue>,
        field_name: &str,
        type_info: &T::TypeInfo,
        kind: FieldKind,
    ) -> Field<'r, DefaultScalarValue> {
        match kind {
            FieldKind::Required => registry.field::<T>(field_name, type_info),
            FieldKind::Optional => registry.field::<Option<T>>(field_name, type_info),
            FieldKind::Array => registry.field::<Vec<Option<T>>>(field_name, type_info),
            _ => registry.field::<Vec<T>>(field_name, type_info),
        }
    }

    fn generate_class_type<'r>(
        class_name: &str,
        d: &ClassDefinition,
        info: &<Self as GraphQLValue>::TypeInfo,
        registry: &mut juniper::Registry<'r, DefaultScalarValue>,
    ) -> juniper::meta::MetaType<'r, DefaultScalarValue>
    where
        DefaultScalarValue: 'r,
    {
        let frames = &info.allframes;
        let mut fields: Vec<_> = d
            .fields()
            .iter()
            .filter_map(|(field_name, field_definition)| {
                if is_reserved_field_name(field_name) {
                    return None;
                }
                Some(
                    if let Some(document_type) = field_definition.document_type(frames) {
                        let field = Self::register_field::<TerminusType<'a, C>>(
                            registry,
                            field_name,
                            &TerminusTypeInfo {
                                class: document_type.to_owned(),
                                allframes: frames.clone(),
                            },
                            field_definition.kind(),
                        );

                        if field_definition.kind().is_collection() {
                            let class_definition =
                                info.allframes.frames[document_type].as_class_definition();
                            let new_info = TerminusTypeInfo {
                                class: document_type.to_owned(),
                                allframes: info.allframes.clone(),
                            };
                            add_arguments(&new_info, registry, field, class_definition)
                        } else {
                            field
                        }
                    } else if let Some(base_type) = field_definition.base_type() {
                        if type_is_bool(base_type) {
                            Self::register_field::<bool>(
                                registry,
                                field_name,
                                &(),
                                field_definition.kind(),
                            )
                        } else if type_is_small_integer(base_type) {
                            Self::register_field::<i32>(
                                registry,
                                field_name,
                                &(),
                                field_definition.kind(),
                            )
                        } else if type_is_big_integer(base_type) {
                            Self::register_field::<BigInt>(
                                registry,
                                field_name,
                                &(),
                                field_definition.kind(),
                            )
                        } else if type_is_float(base_type) {
                            Self::register_field::<f64>(
                                registry,
                                field_name,
                                &(),
                                field_definition.kind(),
                            )
                        } else if type_is_datetime(base_type) {
                            Self::register_field::<DateTime>(
                                registry,
                                field_name,
                                &(),
                                field_definition.kind(),
                            )
                        } else if type_is_decimal(base_type) {
                            Self::register_field::<BigFloat>(
                                registry,
                                field_name,
                                &(),
                                field_definition.kind(),
                            )
                        } else if type_is_json(base_type) {
                            Self::register_field::<GraphQLJSON>(
                                registry,
                                field_name,
                                &(),
                                field_definition.kind(),
                            )
                        } else {
                            // assume stringy
                            Self::register_field::<String>(
                                registry,
                                field_name,
                                &(),
                                field_definition.kind(),
                            )
                        }
                    } else if let Some(enum_type) = field_definition.enum_type(frames) {
                        Self::register_field::<TerminusEnum>(
                            registry,
                            field_name,
                            &(enum_type.to_owned(), frames.clone()),
                            field_definition.kind(),
                        )
                    } else {
                        panic!("No known range for field {:?}", field_definition)
                    },
                )
            })
            .collect();

        let mut inverted_fields: Vec<_> = Vec::new();
        if let Some(inverted_type) = &frames.inverted.classes.get(&info.class) {
            for (field_name, ifd) in inverted_type.domain.iter() {
                let class = &frames.graphql_class_name(&ifd.class);
                if !info.allframes.frames[class].is_document_type() {
                    continue;
                }
                let class_definition = info.allframes.frames[class].as_class_definition();
                let new_info = TerminusTypeInfo {
                    class: class.to_string(),
                    allframes: frames.clone(),
                };
                let field = Self::register_field::<TerminusType<'a, C>>(
                    registry,
                    field_name,
                    &new_info,
                    FieldKind::Set,
                );
                let field = add_arguments(&new_info, registry, field, class_definition);

                inverted_fields.push(field);
            }
        }
        fields.append(&mut inverted_fields);

        let mut path_fields: Vec<_> = Vec::new();
        for class in frames.frames.keys() {
            if !info.allframes.frames[class].is_document_type() {
                continue;
            }
            let field_name = format!("_path_to_{class}");
            let class_definition = info.allframes.frames[class].as_class_definition();
            let new_info = TerminusTypeInfo {
                class: class.to_string(),
                allframes: frames.clone(),
            };
            let field = Self::register_field::<TerminusType<'a, C>>(
                registry,
                &field_name,
                &new_info,
                FieldKind::Set,
            );
            let field = add_arguments(&new_info, registry, field, class_definition);
            let field = field.argument(registry.arg::<String>("path", &()));
            path_fields.push(field);
        }

        fields.append(&mut path_fields);

        let mut applicable_restrictions = Vec::new();
        for restriction in frames.restrictions.values() {
            if restriction.on == class_name {
                applicable_restrictions.push(restriction.id.to_owned());
            }
        }

        if !applicable_restrictions.is_empty() {
            let enum_name = format!("{class_name}_Restriction");
            let type_info = GeneratedEnumTypeInfo {
                name: enum_name,
                values: applicable_restrictions,
            };

            let restriction_field = registry
                .field::<Option<GraphQLJSON>>("_restriction", &())
                .argument(registry.arg::<GeneratedEnum>("name", &type_info));

            fields.push(restriction_field);
        }

        fields.push(registry.field::<ID>("_id", &()));
        fields.push(registry.field::<ID>("_type", &()));

        registry
            .build_object_type::<TerminusType<'a, C>>(info, &fields)
            .into_meta()
    }
}

impl<'a, C: QueryableContextType + 'a> GraphQLType for TerminusType<'a, C> {
    fn name(info: &Self::TypeInfo) -> Option<&str> {
        Some(&info.class)
    }

    fn meta<'r>(
        info: &Self::TypeInfo,
        registry: &mut juniper::Registry<'r, DefaultScalarValue>,
    ) -> juniper::meta::MetaType<'r, DefaultScalarValue>
    where
        DefaultScalarValue: 'r,
    {
        let class = &info.class;
        let allframes = &info.allframes;
        let frame = &allframes.frames[class];
        match frame {
            TypeDefinition::Class(d) => Self::generate_class_type(&class, d, info, registry),
            TypeDefinition::Enum(_) => panic!("no enum expected here"),
        }
    }
}

fn rewind_rdf_list(instance: &dyn Layer, cons_id: u64) -> Option<u64> {
    if let Some(rdf_rest) = instance.predicate_id(RDF_REST) {
        let mut cons = Some(cons_id);
        while let Some(id) = cons {
            let res = instance
                .triples_o(id)
                .filter(|t| t.predicate == rdf_rest)
                .map(|t| t.subject)
                .next();
            if res.is_none() {
                return cons;
            } else {
                cons = res
            }
        }
        cons
    } else {
        None
    }
}

fn subject_has_type(instance: &dyn Layer, subject_id: u64, class: &str) -> bool {
    if let Some(rdf_type_id) = instance.predicate_id(RDF_TYPE) {
        if let Some(class_id) = instance.object_node_id(class) {
            instance.triple_exists(subject_id, rdf_type_id, class_id)
        } else {
            false
        }
    } else {
        false
    }
}

impl<'a, C: QueryableContextType + 'a> GraphQLValue for TerminusType<'a, C> {
    type Context = TerminusContext<'a, C>;

    type TypeInfo = TerminusTypeInfo;

    fn type_name<'i>(&self, info: &'i Self::TypeInfo) -> Option<&'i str> {
        Some(&info.class)
    }

    fn resolve_field(
        &self,
        info: &Self::TypeInfo,
        field_name: &str,
        arguments: &juniper::Arguments,
        executor: &juniper::Executor<Self::Context, DefaultScalarValue>,
    ) -> juniper::ExecutionResult {
        let get_info = || {
            // TODO: should this really be with a `?`? having an id,
            // we should always have had this instance layer at some
            // point. not having it here would be a weird bug.
            let instance = executor.context().instance.as_ref()?;
            if field_name == "_id" {
                return Some(Ok(Value::Scalar(DefaultScalarValue::String(
                    instance.id_subject(self.id)?,
                ))));
            }

            let allframes = &info.allframes;
            let class = &info.class;

            if field_name == "_type" {
                let ty = instance
                    .predicate_id(RDF_TYPE)
                    .and_then(|pid| instance.single_triple_sp(self.id, pid))
                    .and_then(|t| instance.id_object_node(t.object))
                    .map(|ty| {
                        let small_ty = allframes.graphql_class_name(&ty);
                        Ok(Value::Scalar(DefaultScalarValue::String(small_ty)))
                    });
                return ty;
            }

            if let Some(reverse_link) = allframes.reverse_link(class, field_name) {
                let property = &reverse_link.property;
                let domain = &reverse_link.class;
                let kind = &reverse_link.kind;
                let property_expanded = allframes.context.expand_schema(property);
                let domain_uri = allframes.fully_qualified_class_name(domain);
                let field_id = instance.predicate_id(&property_expanded)?;
                // List and array are special since they are *deep* objects
                match kind {
                    FieldKind::List => {
                        let instance1 = instance.clone();
                        let instance2 = instance.clone();
                        let instance3 = instance.clone();
                        let object_ids = instance
                            .triples_o(self.id)
                            .flat_map(move |t| {
                                instance1
                                    .predicate_id(RDF_FIRST)
                                    .filter(|rdf_first| t.predicate == *rdf_first)
                                    .map(|_| t.subject)
                            })
                            .flat_map(move |cons| rewind_rdf_list(&instance2, cons))
                            .flat_map(move |o| {
                                instance3
                                    .triples_o(o)
                                    .filter(|t| {
                                        t.predicate == field_id
                                            && subject_has_type(&instance3, t.subject, &domain_uri)
                                    })
                                    .map(|t| t.subject)
                                    .next()
                            });
                        collect_into_graphql_list(
                            Some(domain),
                            None,
                            false,
                            executor,
                            info,
                            arguments,
                            ClonableIterator::new(CachedClonableIterator::new(object_ids)),
                            instance,
                        )
                    }
                    FieldKind::Array => {
                        let instance1 = instance.clone();
                        let instance2 = instance.clone();
                        let instance3 = instance.clone();
                        let object_ids = instance
                            .triples_o(self.id)
                            .flat_map(move |t| {
                                instance1
                                    .predicate_id(SYS_VALUE)
                                    .filter(|sys_value| t.predicate == *sys_value)
                                    .map(|_| t.subject)
                            })
                            .flat_map(move |o| {
                                instance2
                                    .triples_o(o)
                                    .filter(|t| {
                                        t.predicate == field_id
                                            && subject_has_type(&instance3, t.subject, &domain_uri)
                                    })
                                    .map(|t| t.subject)
                                    .next()
                            });
                        collect_into_graphql_list(
                            Some(domain),
                            None,
                            false,
                            executor,
                            info,
                            arguments,
                            ClonableIterator::new(CachedClonableIterator::new(object_ids)),
                            instance,
                        )
                    }
                    _ => {
                        let instance1 = instance.clone();
                        let object_ids = instance
                            .triples_o(self.id)
                            .filter(move |t| {
                                t.predicate == field_id
                                    && subject_has_type(&instance1, t.subject, &domain_uri)
                            })
                            .map(|t| t.subject);
                        collect_into_graphql_list(
                            Some(domain),
                            None,
                            false,
                            executor,
                            info,
                            arguments,
                            ClonableIterator::new(CachedClonableIterator::new(object_ids)),
                            instance,
                        )
                    }
                }
            } else if is_path_field_name(field_name) {
                const PREFIX_LEN: usize = "_path_to_".len();
                let class = &field_name[PREFIX_LEN..];
                let ids = vec![self.id].into_iter();
                collect_into_graphql_list(
                    Some(class),
                    None,
                    false,
                    executor,
                    info,
                    arguments,
                    ClonableIterator::new(CachedClonableIterator::new(ids)),
                    instance,
                )
            } else if field_name == "_restriction" {
                // fetch argument
                let restriction_enum_value: GeneratedEnum = arguments.get("name")?;
                let original_restriction = &allframes
                    .class_renaming
                    .get_by_left(&restriction_enum_value.value)
                    .unwrap();

                let result =
                    id_matches_restriction(executor.context(), original_restriction, self.id);

                match result {
                    Ok(Some(reason)) => Some(Ok(graphql_value!(reason))),
                    Ok(None) => Some(Ok(graphql_value!(None))),
                    Err(e) => Some(Err(e)),
                }
            } else {
                let frame = &allframes.frames[&info.class];
                let field_name_expanded: String;
                let doc_type;
                let enum_type;
                let kind;
                let is_json;
                match frame {
                    TypeDefinition::Class(c) => {
                        let field = &c.resolve_field(&field_name.to_string());
                        field_name_expanded = c.fully_qualified_property_name(
                            &allframes.context,
                            &field_name.to_string(),
                        );

                        doc_type = field.document_type(allframes);
                        enum_type = field.enum_type(allframes);
                        kind = field.kind();
                        is_json = field.is_json_type();
                    }
                    _ => panic!("expected only a class at this level"),
                }
                let field_id_opt = instance.predicate_id(&field_name_expanded);
                if field_id_opt.is_none() {
                    match kind {
                        FieldKind::Array
                        | FieldKind::List
                        | FieldKind::Cardinality
                        | FieldKind::Set => return Some(Ok(graphql_value!([]))),
                        _ => return None,
                    }
                };
                let field_id = field_id_opt.unwrap();
                match kind {
                    FieldKind::Required => {
                        let object_id = instance.single_triple_sp(self.id, field_id)?.object;
                        extract_fragment(
                            executor, info, instance, object_id, doc_type, enum_type, is_json,
                        )
                    }
                    FieldKind::Optional => {
                        let object_id = instance
                            .single_triple_sp(self.id, field_id)
                            .map(|t| t.object);
                        match object_id {
                            Some(object_id) => extract_fragment(
                                executor, info, instance, object_id, doc_type, enum_type, is_json,
                            ),
                            None => Some(Ok(Value::Null)),
                        }
                    }
                    FieldKind::Set => {
                        let object_ids = ClonableIterator::new(CachedClonableIterator::new(
                            instance.triples_sp(self.id, field_id).map(|t| t.object),
                        ));
                        collect_into_graphql_list(
                            doc_type, enum_type, is_json, executor, info, arguments, object_ids,
                            instance,
                        )
                    }
                    FieldKind::Cardinality => {
                        // pretty much a set actually
                        let object_ids = ClonableIterator::new(CachedClonableIterator::new(
                            instance.triples_sp(self.id, field_id).map(|t| t.object),
                        ));
                        collect_into_graphql_list(
                            doc_type, enum_type, is_json, executor, info, arguments, object_ids,
                            instance,
                        )
                    }
                    FieldKind::List => {
                        let list_id = instance
                            .single_triple_sp(self.id, field_id)
                            .expect("list element expected but not found")
                            .object;
                        let object_ids =
                            ClonableIterator::new(CachedClonableIterator::new(RdfListIterator {
                                layer: instance,
                                cur: list_id,
                                rdf_first_id: instance.predicate_id(RDF_FIRST),
                                rdf_rest_id: instance.predicate_id(RDF_REST),
                                rdf_nil_id: instance.subject_id(RDF_NIL),
                            }));
                        collect_into_graphql_list(
                            doc_type, enum_type, is_json, executor, info, arguments, object_ids,
                            instance,
                        )
                    }
                    FieldKind::Array => {
                        let array_element_ids: Box<dyn Iterator<Item = IdTriple> + Send> =
                            Box::new(instance.triples_sp(self.id, field_id));
                        let sys_index_ids = retrieve_all_index_ids(instance);
                        let array_iterator = SimpleArrayIterator(ArrayIterator {
                            layer: instance,
                            it: array_element_ids.peekable(),
                            subject: self.id,
                            predicate: field_id,
                            last_index: None,
                            sys_index_ids: &sys_index_ids,
                            sys_value_id: instance.predicate_id(SYS_VALUE),
                        });

                        let mut elements: Vec<_> = array_iterator.collect();
                        elements.sort();
                        let elements_iterator = ClonableIterator::new(CachedClonableIterator::new(
                            elements.into_iter().map(|(_, elt)| elt),
                        ));
                        collect_into_graphql_list(
                            doc_type,
                            enum_type,
                            is_json,
                            executor,
                            info,
                            arguments,
                            elements_iterator,
                            instance,
                        )
                    }
                }
            }
        };

        let x = get_info();
        match x {
            Some(r) => r,
            None => Ok(Value::Null),
        }
    }
}

fn extract_fragment<'a, C: QueryableContextType + 'a>(
    executor: &juniper::Executor<TerminusContext<'a, C>, DefaultScalarValue>,
    info: &TerminusTypeInfo,
    instance: &SyncStoreLayer,
    object_id: u64,
    doc_type: Option<&str>,
    enum_type: Option<&str>,
    is_json: bool,
) -> Option<Result<juniper::Value, juniper::FieldError>> {
    if let Some(doc_type) = doc_type {
        Some(executor.resolve(
            &TerminusTypeInfo {
                class: doc_type.to_string(),
                allframes: info.allframes.clone(),
            },
            &TerminusType::new(object_id),
        ))
    } else if let Some(enum_type) = enum_type {
        let value = extract_enum_fragment(info, instance, object_id, enum_type);
        Some(Ok(value))
    } else if is_json {
        let val = extract_json_fragment(instance, object_id);
        Some(Ok(val))
    } else {
        let obj = instance.id_object(object_id)?;
        let val = obj.value_ref().unwrap_or_else(|| panic!("{:?}", &obj));
        Some(Ok(value_to_graphql(val)))
    }
}

fn extract_enum_fragment(
    info: &TerminusTypeInfo,
    instance: &SyncStoreLayer,
    object_id: u64,
    enum_type: &str,
) -> juniper::Value {
    let enum_uri = instance.id_object_node(object_id).unwrap();
    let enum_value = enum_node_to_value(enum_type, &enum_uri);
    let enum_definition = info.allframes.frames[enum_type].as_enum_definition();
    juniper::Value::Scalar(DefaultScalarValue::String(
        enum_definition.name_value(&enum_value).to_string(),
    ))
}

fn extract_json_fragment(instance: &SyncStoreLayer, object_id: u64) -> juniper::Value {
    let context = GetDocumentContext::new_json(Some(instance.clone()), true, false);
    let json = serde_json::Value::Object(context.get_id_document(object_id));
    juniper::Value::Scalar(DefaultScalarValue::String(json.to_string()))
}

fn is_path_field_name(field_name: &str) -> bool {
    field_name.starts_with("_path_to_")
}

/// An enum type that is generated dynamically
pub struct GeneratedEnumTypeInfo {
    pub name: String,
    pub values: Vec<String>,
}

/// An enum value that is generated dynamically
pub struct GeneratedEnum {
    pub value: String,
}

impl GraphQLValue for GeneratedEnum {
    type Context = ();

    type TypeInfo = GeneratedEnumTypeInfo;

    fn type_name<'i>(&self, info: &'i Self::TypeInfo) -> Option<&'i str> {
        Some(&info.name)
    }
}

impl GraphQLType for GeneratedEnum {
    fn name(info: &Self::TypeInfo) -> Option<&str> {
        Some(&info.name)
    }

    fn meta<'r>(
        info: &Self::TypeInfo,
        registry: &mut Registry<'r, DefaultScalarValue>,
    ) -> juniper::meta::MetaType<'r, DefaultScalarValue>
    where
        DefaultScalarValue: 'r,
    {
        let values: Vec<_> = info
            .values
            .iter()
            .map(|v| EnumValue {
                name: v.to_string(),
                description: None,
                deprecation_status: DeprecationStatus::Current,
            })
            .collect();
        registry
            .build_enum_type::<GeneratedEnum>(info, &values)
            .into_meta()
    }
}

impl FromInputValue for GeneratedEnum {
    fn from_input_value(v: &InputValue<DefaultScalarValue>) -> Option<Self> {
        match v {
            InputValue::Enum(value) => Some(Self {
                value: value.to_owned(),
            }),
            InputValue::Scalar(DefaultScalarValue::String(value)) => Some(Self {
                value: value.to_owned(),
            }),
            _ => None,
        }
    }
}

pub struct TerminusEnum {
    pub value: String,
}

impl GraphQLType for TerminusEnum {
    fn name(info: &Self::TypeInfo) -> Option<&str> {
        Some(&info.0)
    }

    fn meta<'r>(
        info: &Self::TypeInfo,
        registry: &mut juniper::Registry<'r, DefaultScalarValue>,
    ) -> juniper::meta::MetaType<'r, DefaultScalarValue>
    where
        DefaultScalarValue: 'r,
    {
        if let TypeDefinition::Enum(e) = &info.1.frames[&info.0] {
            let values: Vec<_> = e
                .values
                .iter()
                .map(|v| -> EnumValue {
                    EnumValue {
                        name: v.to_string(),
                        description: None,
                        deprecation_status: DeprecationStatus::Current,
                    }
                })
                .collect();

            registry
                .build_enum_type::<TerminusEnum>(info, &values)
                .into_meta()
        } else {
            panic!("tried to build meta for enum but this is not an enum");
        }
    }
}

impl FromInputValue for TerminusEnum {
    fn from_input_value(v: &InputValue<DefaultScalarValue>) -> Option<Self> {
        match v {
            InputValue::Enum(value) => Some(Self {
                value: value.to_owned(),
            }),
            InputValue::Scalar(DefaultScalarValue::String(value)) => Some(Self {
                value: value.to_owned(),
            }),
            _ => None,
        }
    }
}

impl GraphQLValue for TerminusEnum {
    type Context = ();

    type TypeInfo = (String, Arc<AllFrames>);

    fn type_name<'i>(&self, _info: &'i Self::TypeInfo) -> Option<&'i str> {
        Some("TerminusEnum")
    }
}

struct SimpleArrayIterator<'a, L: Layer>(ArrayIterator<'a, L>);

impl<'a, L: Layer> Iterator for SimpleArrayIterator<'a, L> {
    type Item = (Vec<usize>, u64);

    fn next(&mut self) -> Option<Self::Item> {
        let result = self.0.next();
        match result {
            None => None,
            Some(element) => {
                let mut index = None;
                std::mem::swap(&mut index, &mut self.0.last_index);

                Some((index.unwrap(), element))
            }
        }
    }
}

fn collect_into_graphql_list<'a, C: QueryableContextType>(
    doc_type: Option<&'a str>,
    enum_type: Option<&'a str>,
    is_json: bool,
    executor: &'a juniper::Executor<TerminusContext<C>>,
    info: &'a TerminusTypeInfo,
    arguments: &'a juniper::Arguments,
    object_ids: ClonableIterator<'a, u64>,
    instance: &'a SyncStoreLayer,
) -> Option<Result<Value, juniper::FieldError>> {
    if let Some(doc_type) = doc_type {
        let object_ids = match executor.context().instance.as_ref() {
            Some(instance) => run_filter_query(
                executor.context(),
                instance,
                &info.allframes.context,
                arguments,
                doc_type,
                &info.allframes,
                Some(object_ids),
            ),
            None => vec![],
        };
        let subdocs: Vec<_> = object_ids.into_iter().map(TerminusType::new).collect();
        Some(executor.resolve(
            &TerminusTypeInfo {
                class: doc_type.to_string(),
                allframes: info.allframes.clone(),
            },
            &subdocs,
        ))
    } else if let Some(enum_type) = enum_type {
        let vals: Vec<_> = object_ids
            .map(|o| extract_enum_fragment(info, instance, o, enum_type))
            .collect();
        Some(Ok(Value::List(vals)))
    } else if is_json {
        let vals: Vec<_> = object_ids
            .map(|o| extract_json_fragment(instance, o))
            .collect();
        Some(Ok(Value::List(vals)))
    } else {
        let vals: Vec<_> = object_ids
            .map(|o| {
                let val = instance.id_object_value(o).unwrap();
                value_to_graphql(&val)
            })
            .collect();
        Some(Ok(Value::List(vals)))
    }
}

#[derive(GraphQLEnum, Clone, Copy)]
pub enum TerminusOrdering {
    Asc,
    Desc,
}

pub struct TerminusOrderBy {
    pub fields: Vec<(String, TerminusOrdering)>,
}

impl FromInputValue for TerminusOrderBy {
    fn from_input_value(v: &InputValue<DefaultScalarValue>) -> Option<Self> {
        if let InputValue::Object(o) = v {
            let fields: Vec<_> = o
                .iter()
                .map(|(k, v)| {
                    (
                        k.item.to_owned(),
                        TerminusOrdering::from_input_value(&v.item).unwrap(),
                    )
                })
                .collect();

            Some(Self { fields })
        } else {
            None
        }
    }
}

impl GraphQLType for TerminusOrderBy {
    fn name(info: &Self::TypeInfo) -> Option<&str> {
        Some(&info.ordering_name)
    }

    fn meta<'r>(
        info: &Self::TypeInfo,
        registry: &mut Registry<'r, DefaultScalarValue>,
    ) -> juniper::meta::MetaType<'r, DefaultScalarValue>
    where
        DefaultScalarValue: 'r,
    {
        let frames = &info.allframes;
        if let TypeDefinition::Class(d) = &frames.frames[&info.type_name] {
            let arguments: Vec<_> = d
                .fields
                .iter()
                .filter_map(|(field_name, field_definition)| {
                    if field_definition.base_type().is_some() {
                        Some(registry.arg::<Option<TerminusOrdering>>(field_name, &()))
                    } else {
                        None
                    }
                })
                .collect();

            registry
                .build_input_object_type::<TerminusOrderBy>(info, &arguments)
                .into_meta()
        } else {
            panic!("shouldn't be here");
        }
    }
}

impl GraphQLValue for TerminusOrderBy {
    type Context = ();

    type TypeInfo = TerminusOrderingInfo;

    fn type_name<'i>(&self, info: &'i Self::TypeInfo) -> Option<&'i str> {
        Some(&info.ordering_name)
    }

    fn resolve_field(
        &self,
        _info: &Self::TypeInfo,
        _field_name: &str,
        _arguments: &juniper::Arguments<DefaultScalarValue>,
        _executor: &juniper::Executor<Self::Context, DefaultScalarValue>,
    ) -> juniper::ExecutionResult<DefaultScalarValue> {
        panic!("GraphQLValue::resolve_field() must be implemented by objects and interfaces");
    }
}

#[derive(Debug, Clone)]
pub struct BigInt(pub String);

#[juniper::graphql_scalar(
    name = "BigInt",
    description = "The `BigInt` scalar type represents non-fractional signed whole numeric values."
)]
impl<S> GraphQLScalar for BigInt
where
    S: juniper::ScalarValue,
{
    fn resolve(&self) -> juniper::Value {
        juniper::Value::scalar(self.0.to_owned())
    }

    fn from_input_value(value: &juniper::InputValue) -> Option<Self> {
        value.as_string_value().map(|s| Self(s.to_owned()))
    }

    fn from_str<'a>(value: juniper::ScalarToken<'a>) -> juniper::ParseScalarResult<'a, S> {
        <String as juniper::ParseScalarValue<S>>::from_str(value)
    }
}

#[derive(Debug, Clone)]
pub struct GraphQLJSON(pub String);

#[juniper::graphql_scalar(name = "JSON", description = "An arbitrary JSON value.")]
impl<S> GraphQLScalar for GraphQLJSON
where
    S: juniper::ScalarValue,
{
    fn resolve(&self) -> juniper::Value {
        juniper::Value::scalar(self.0.to_owned())
    }

    fn from_input_value(value: &juniper::InputValue) -> Option<Self> {
        value.as_string_value().map(|s| Self(s.to_owned()))
    }

    fn from_str<'a>(value: juniper::ScalarToken<'a>) -> juniper::ParseScalarResult<'a, S> {
        <String as juniper::ParseScalarValue<S>>::from_str(value)
    }
}

#[derive(Debug, Clone)]
pub struct DateTime(pub String);

#[juniper::graphql_scalar(
    name = "DateTime",
    description = "The `DateTime` scalar type represents a date encoded as a string using the RFC 3339 profile of the ISO 8601 standard for representation of dates and times using the Gregorian calendar."
)]
impl<S> GraphQLScalar for DateTime
where
    S: juniper::ScalarValue,
{
    fn resolve(&self) -> juniper::Value {
        juniper::Value::scalar(self.0.to_owned())
    }

    fn from_input_value(value: &juniper::InputValue) -> Option<Self> {
        value.as_string_value().map(|s| Self(s.to_owned()))
    }

    fn from_str<'a>(value: juniper::ScalarToken<'a>) -> juniper::ParseScalarResult<'a, S> {
        <String as juniper::ParseScalarValue<S>>::from_str(value)
    }
}

#[derive(Debug, Clone)]
pub struct BigFloat(pub String);

#[juniper::graphql_scalar(
    name = "BigFloat",
    description = "The `BigFloat` scalar type represents an arbitrary precision decimal."
)]
impl<S> GraphQLScalar for BigFloat
where
    S: juniper::ScalarValue,
{
    fn resolve(&self) -> juniper::Value {
        juniper::Value::scalar(self.0.to_owned())
    }

    fn from_input_value(value: &juniper::InputValue) -> Option<Self> {
        value.as_string_value().map(|s| Self(s.to_owned()))
    }

    fn from_str<'a>(value: juniper::ScalarToken<'a>) -> juniper::ParseScalarResult<'a, S> {
        <String as juniper::ParseScalarValue<S>>::from_str(value)
    }
}
