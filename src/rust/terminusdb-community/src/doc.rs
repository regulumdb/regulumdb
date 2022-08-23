use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap, HashSet};
use std::io::Write;
use std::iter::Peekable;
use std::sync::{mpsc, Arc};

use crate::terminus_store::store::sync::*;
use crate::terminus_store::*;

use serde_json::map;
use serde_json::{Map, Value};
use urlencoding;

use super::consts::*;
use super::prefix::PrefixContracter;
use super::schema::*;
use super::value::*;

use rayon::prelude::*;
use swipl::prelude::*;

pub struct GetDocumentContext<L: Layer> {
    layer: Option<L>,
    prefixes: PrefixContracter,
    types: HashSet<u64>,
    document_types: HashSet<u64>,
    unfoldables: HashSet<u64>,
    enums: HashMap<u64, String>,
    set_pairs: HashSet<(u64, u64)>,
    rdf_type_id: Option<u64>,
    rdf_first_id: Option<u64>,
    rdf_rest_id: Option<u64>,
    rdf_nil_id: Option<u64>,
    rdf_list_id: Option<u64>,
    sys_index_ids: Vec<u64>,
    sys_array_id: Option<u64>,
    sys_value_id: Option<u64>,
    sys_json_type_id: Option<u64>,
    sys_json_document_type_id: Option<u64>,
    unfold: bool,
    minimized: bool,
}

impl<L: Layer> GetDocumentContext<L> {
    #[inline(never)]
    pub fn new<SL: Layer>(
        schema: &SL,
        instance: Option<L>,
        compress: bool,
        unfold: bool,
        minimized: bool,
    ) -> GetDocumentContext<L> {
        let prefixes;
        if compress {
            prefixes = prefix_contracter_from_schema_layer(schema);
        } else {
            prefixes = PrefixContracter::new(std::iter::empty());
        }

        let mut rdf_type_id = None;
        let mut rdf_first_id = None;
        let mut rdf_rest_id = None;
        let mut rdf_nil_id = None;
        let mut rdf_list_id = None;
        let mut sys_json_type_id = None;
        let mut sys_json_document_type_id = None;
        let mut types: HashSet<u64>;
        let mut document_types: HashSet<u64>;
        let unfoldables: HashSet<u64>;
        let mut enums: HashMap<u64, String>;
        let mut set_pairs: HashSet<(u64, u64)>;
        let mut sys_index_ids: Vec<u64>;
        let mut sys_array_id = None;
        let mut sys_value_id = None;

        if let Some(ref instance) = instance {
            let schema_document_type_ids = get_document_type_ids_from_schema(schema);
            let schema_type_ids = get_type_ids_from_schema(schema);
            let schema_unfoldable_ids = get_unfoldable_ids_from_schema(schema);
            let schema_enum_ids = get_enum_ids_from_schema(schema);

            document_types =
                schema_to_instance_types(schema, instance, schema_document_type_ids).collect();
            types = schema_to_instance_types(schema, instance, schema_type_ids).collect();

            unfoldables =
                schema_to_instance_types(schema, instance, schema_unfoldable_ids).collect();

            enums = HashMap::new();
            for schema_enum_id in schema_enum_ids {
                let enum_expanded = schema.id_object_node(schema_enum_id).unwrap();
                if let Some(instance_enum_id) = instance.object_node_id(&enum_expanded) {
                    // an enum node is its type concatenated with a / followed by an uri encoded string corresponding to its value
                    let pos = enum_expanded.rfind('/').unwrap();
                    let encoded = &enum_expanded[pos + 1..];

                    let decoded = urlencoding::decode(encoded).unwrap().to_string();
                    enums.insert(instance_enum_id, decoded);
                }
            }

            let schema_set_pairs = get_set_pairs_from_schema(schema);
            set_pairs = HashSet::new();
            for (schema_type_id, schema_predicate_id) in schema_set_pairs {
                if let Some(type_id) = translate_subject_id(schema, instance, schema_type_id) {
                    if let Some(predicate_id) =
                        translate_predicate_id(schema, instance, schema_predicate_id)
                    {
                        set_pairs.insert((type_id, predicate_id));
                    }
                }
            }

            rdf_type_id = instance.predicate_id(RDF_TYPE);
            rdf_first_id = instance.predicate_id(RDF_FIRST);
            rdf_rest_id = instance.predicate_id(RDF_REST);
            rdf_nil_id = instance.object_node_id(RDF_NIL);
            rdf_list_id = instance.object_node_id(RDF_LIST);
            sys_json_type_id = instance.object_node_id(SYS_JSON);
            sys_json_document_type_id = instance.object_node_id(SYS_JSON_DOCUMENT);

            if let Some(sys_json_document_type_id) = sys_json_document_type_id {
                document_types.insert(sys_json_document_type_id);
            }

            sys_index_ids = Vec::new();
            let mut index_str = SYS_INDEX.to_string();
            let orig_len = index_str.len();
            let mut ix = 1;

            loop {
                if let Some(index_id) = instance.predicate_id(&index_str) {
                    sys_index_ids.push(index_id);
                    ix += 1;
                    let ix_s = ix.to_string();
                    index_str.truncate(orig_len);
                    index_str.push_str(&ix_s);
                } else {
                    break;
                }
            }

            sys_array_id = instance.object_node_id(SYS_ARRAY);
            sys_value_id = instance.predicate_id(SYS_VALUE);
        } else {
            types = HashSet::with_capacity(0);
            document_types = HashSet::with_capacity(0);
            unfoldables = HashSet::with_capacity(0);
            enums = HashMap::with_capacity(0);
            set_pairs = HashSet::with_capacity(0);
            sys_index_ids = Vec::with_capacity(0);
        }

        GetDocumentContext {
            layer: instance,

            prefixes,
            types,
            document_types,
            unfoldables,
            enums,
            set_pairs,
            rdf_type_id,
            rdf_first_id,
            rdf_rest_id,
            rdf_nil_id,
            rdf_list_id,
            sys_index_ids,
            sys_array_id,
            sys_value_id,

            sys_json_type_id,
            sys_json_document_type_id,
            unfold,
            minimized,
        }
    }

    #[inline(always)]
    fn layer(&self) -> &L {
        self.layer.as_ref().unwrap()
    }

    #[inline(never)]
    pub fn get_document(&self, iri: &str) -> Option<Map<String, Value>> {
        if self.layer.is_some() {
            if let Some(id) = self.layer().subject_id(iri) {
                Some(self.get_id_document(id))
            } else {
                None
            }
        } else {
            None
        }
    }

    #[inline(never)]
    fn get_field(&self, object: u64) -> Result<Value, StackEntry<L>> {
        if let Some(val) = self.enums.get(&object) {
            Ok(Value::String(val.clone()))
        } else if Some(object) == self.rdf_nil_id {
            Ok(Value::Array(vec![]))
        } else {
            match self.get_doc_stub(object, true) {
                // it's not a terminator so we will need to descend into it. That is, we would need to descend into it if there were any children, so let's check.
                Ok((doc, type_id, fields, json)) => Err(StackEntry::Document {
                    doc,
                    type_id,
                    fields: Some(fields),
                    json,
                }),
                Err(v) => Ok(v),
            }
        }
    }

    #[inline(never)]
    fn add_field(&self, obj: &mut Map<String, Value>, key: &str, value: Value, is_set: bool) {
        // add a field, but if the field is already there, make it a collection
        match obj.entry(key) {
            map::Entry::Vacant(e) => {
                if is_set {
                    e.insert(Value::Array(vec![value]));
                } else {
                    e.insert(value);
                }
            }
            map::Entry::Occupied(mut e) => {
                let mut v = e.get_mut();
                match v {
                    Value::Array(a) => {
                        a.push(value);
                    }
                    _ => {
                        let mut a = Vec::new();
                        let mut old_v = Value::Null;
                        std::mem::swap(&mut old_v, &mut v);
                        a.push(old_v);
                        a.push(value);
                        *v = Value::Array(a);
                    }
                }
            }
        }
    }

    #[inline(never)]
    fn get_list_iter(&self, id: u64) -> Peekable<RdfListIterator<L>> {
        RdfListIterator {
            layer: self.layer(),
            cur: id,
            rdf_first_id: self.rdf_first_id,
            rdf_rest_id: self.rdf_rest_id,
            rdf_nil_id: self.rdf_nil_id,
        }
        .peekable()
    }

    #[inline(never)]
    fn get_array_iter(&self, stack_entry: &mut StackEntry<L>) -> ArrayIterator<L> {
        if let StackEntry::Document { fields, .. } = stack_entry {
            let mut it = None;
            std::mem::swap(&mut it, fields);
            let mut it = it.unwrap();
            let t = it.peek().unwrap();
            let subject = t.subject;
            let predicate = t.predicate;
            return ArrayIterator {
                layer: self.layer(),
                it,
                subject,
                predicate,
                last_index: None,
                sys_index_ids: &self.sys_index_ids,
                sys_value_id: self.sys_value_id,
            };
        } else {
            panic!("array is not a field of a document");
        }
    }

    #[inline(never)]
    fn get_doc_stub(
        &self,
        id: u64,
        terminate: bool,
    ) -> Result<
        (
            Map<String, Value>,
            Option<u64>,
            Peekable<Box<dyn Iterator<Item = IdTriple> + Send>>,
            bool,
        ),
        Value,
    > {
        let id_name = self.layer().id_object(id).unwrap();
        if let Some(v) = id_name.value_ref() {
            // this is not actually a document but a value
            return Err(value_string_to_json(v));
        }

        // we know id_name is properly a node
        let id_name = id_name.node().unwrap();
        let id_name_contracted = self.prefixes.instance_contract(&id_name).to_string();

        let rdf_type_id = self.rdf_type_id;
        let mut fields = (Box::new(
            self.layer()
                .triples_s(id)
                .filter(move |f| Some(f.predicate) != rdf_type_id),
        ) as Box<dyn Iterator<Item = IdTriple> + Send>)
            .peekable();

        let mut type_id = None;
        let mut type_name_contracted: Option<String> = None;
        let mut json = false;
        if let Some(rdf_type_id) = self.rdf_type_id {
            if let Some(t) = self.layer().single_triple_sp(id, rdf_type_id) {
                if terminate
                    && (!self.unfold
                        || (self.document_types.contains(&t.object)
                            && !self.unfoldables.contains(&t.object)))
                {
                    return Err(Value::String(id_name_contracted));
                }

                type_id = Some(t.object);
                if Some(t.object) == self.sys_json_document_type_id
                    || Some(t.object) == self.sys_json_type_id
                {
                    json = true;
                }

                if !json {
                    // json objects are special. We don't care about their type names.
                    // for other types, we do care, so convert to string format.
                    let type_name = self.layer().id_object_node(t.object).unwrap();
                    type_name_contracted =
                        Some(self.prefixes.schema_contract(&type_name).to_string());
                }
            }
        }

        if type_id.is_none() && fields.peek().is_none() {
            // we're actually dealing with a raw id here
            Err(Value::String(id_name_contracted))
        } else {
            let mut result = Map::new();

            if type_id.is_none() || type_id != self.sys_json_type_id {
                // we only care about the id for non-json types, and for the top level json documents. Json (sub)documents should not include an id.
                result.insert("@id".to_string(), Value::String(id_name_contracted));
            }
            if let Some(tn) = type_name_contracted {
                // since we only contract types for non-json types, this will only add the @type for actual defined types, not the json types.
                result.insert("@type".to_string(), Value::String(tn));
            }

            Ok((result, type_id, fields, json))
        }
    }

    #[inline(never)]
    pub fn get_id_document(&self, id: u64) -> Map<String, Value> {
        if self.layer.is_none() {
            panic!("expected id to point at document: {}", id);
        }

        let mut stack = Vec::new();

        let (doc, type_id, fields, json) = self.get_doc_stub(id, false).unwrap();
        stack.push(StackEntry::Document {
            doc,
            type_id,
            fields: Some(fields),
            json,
        });

        loop {
            let cur = stack.last_mut().unwrap();
            let is_json = cur.is_json();
            if let Some(next_obj) = cur.peek() {
                // let's first see if this object is one of the expected types
                if is_json || cur.is_document() {
                    if let Some(rdf_type_id) = self.rdf_type_id {
                        if let Some(t) = self.layer().single_triple_sp(next_obj, rdf_type_id) {
                            if Some(t.object) == self.sys_array_id {
                                let array_iter = self.get_array_iter(cur);
                                stack.push(StackEntry::Array(ArrayStackEntry {
                                    collect: Vec::new(),
                                    entries: array_iter,
                                }));
                                continue;
                            } else if Some(t.object) == self.rdf_list_id {
                                let list_iter = self.get_list_iter(next_obj);
                                stack.push(StackEntry::List {
                                    collect: Vec::new(),
                                    entries: list_iter,
                                    json: is_json,
                                });
                                continue;
                            }
                        }
                    }
                }

                // it's not one of the special types, treat it as an ordinary field.
                match self.get_field(next_obj) {
                    Ok(val) => {
                        cur.integrate_value(self, val);
                    }
                    Err(entry) => {
                        // We need to iterate deeper, so add it to the stack without iterating past the field.
                        stack.push(entry);
                    }
                }
            } else {
                // done!
                let cur = stack.pop().unwrap();
                if let Some(parent) = stack.last_mut() {
                    parent.integrate(self, cur);
                } else {
                    // we're done, this was the root, time to return!
                    match cur {
                        StackEntry::Document { doc, .. } => return doc,
                        _ => panic!("unexpected element at stack top"),
                    }
                }
            }
        }
    }
}

enum StackEntry<'a, L: Layer> {
    Document {
        doc: Map<String, Value>,
        type_id: Option<u64>,
        fields: Option<Peekable<Box<dyn Iterator<Item = IdTriple> + Send>>>,
        json: bool,
    },
    List {
        collect: Vec<Value>,
        entries: Peekable<RdfListIterator<'a, L>>,
        json: bool,
    },
    Array(ArrayStackEntry<'a, L>),
}

impl<'a, L: Layer> StackEntry<'a, L> {
    fn is_document(&self) -> bool {
        match self {
            Self::Document { .. } => true,
            _ => false,
        }
    }

    fn is_json(&self) -> bool {
        match self {
            Self::Document { json, .. } => *json,
            Self::List { json, .. } => *json,
            _ => false,
        }
    }
}

struct ArrayStackEntry<'a, L: Layer> {
    collect: Vec<(Vec<usize>, Value)>,
    entries: ArrayIterator<'a, L>,
}

struct ArrayIterator<'a, L: Layer> {
    layer: &'a L,
    it: Peekable<Box<dyn Iterator<Item = IdTriple> + Send>>,
    subject: u64,
    predicate: u64,
    last_index: Option<Vec<usize>>,
    sys_index_ids: &'a [u64],
    sys_value_id: Option<u64>,
}

impl<'a, L: Layer> Iterator for ArrayIterator<'a, L> {
    type Item = u64;

    fn next(&mut self) -> Option<u64> {
        if let Some(t) = self.it.peek() {
            if t.subject == self.subject && t.predicate == self.predicate {
                let mut indexes = Vec::new();
                for index_id in self.sys_index_ids {
                    if let Some(index_triple) = self.layer.single_triple_sp(t.object, *index_id) {
                        let index_value = self.layer.id_object_value(index_triple.object).unwrap();
                        let index = value_string_to_usize(&index_value);
                        indexes.push(index);
                    } else {
                        // no more indexes to come
                        break;
                    }
                }
                indexes.reverse();

                let value_id = self
                    .layer
                    .single_triple_sp(t.object, *self.sys_value_id.as_ref().unwrap())
                    .expect("expected value property on array element")
                    .object;

                // now that we know for sure that we got everything and this is indeed an array cell, let's actually move the field iterator.
                self.it.next().unwrap();
                self.last_index = Some(indexes);
                return Some(value_id);
            }
        }

        None
    }
}

impl<'a, L: Layer> StackEntry<'a, L> {
    #[inline(never)]
    fn peek(&mut self) -> Option<u64> {
        match self {
            Self::Document { fields, .. } => fields.as_mut().unwrap().peek().map(|t| t.object),
            Self::List { entries, .. } => entries.peek().map(|x| *x),
            Self::Array(a) => a.entries.next(),
        }
    }

    #[inline(never)]
    fn into_value(self) -> Value {
        match self {
            Self::Document { doc, .. } => Value::Object(doc),
            Self::List { collect, .. } => Value::Array(collect),
            Self::Array { .. } => panic!("cannot directly turn array into a value"),
        }
    }

    #[inline(never)]
    fn integrate(&mut self, context: &GetDocumentContext<L>, child: StackEntry<'a, L>) {
        match child {
            StackEntry::Array(a) => self.integrate_array(context, a),
            _ => self.integrate_value(context, child.into_value()),
        }
    }

    #[inline(never)]
    fn integrate_array(&mut self, context: &GetDocumentContext<L>, array: ArrayStackEntry<'a, L>) {
        // self has to be an object, let's make sure of that.
        match self {
            Self::Document { doc, fields, .. } => {
                *fields = Some(array.entries.it);

                let value = collect_array(array.collect);

                let p_name = context
                    .layer()
                    .id_predicate(array.entries.predicate)
                    .unwrap();
                let p_name_contracted = context.prefixes.schema_contract(&p_name).to_string();
                context.add_field(doc, &p_name_contracted, value, false);
            }
            _ => panic!("unexpected parent type of array"),
        }
    }

    #[inline(never)]
    fn integrate_value(&mut self, context: &GetDocumentContext<L>, value: Value) {
        match self {
            Self::Document {
                doc,
                fields,
                type_id,
                ..
            } => {
                // we previously peeked a field and decided we needed to recurse deeper.
                // this is the time to pop it.
                let t = fields.as_mut().unwrap().next().unwrap();
                let is_set = type_id
                    .map(|type_id| context.set_pairs.contains(&(type_id, t.predicate)))
                    .unwrap_or(false);
                let p_name = context.layer().id_predicate(t.predicate).unwrap();
                let p_name_contracted = context.prefixes.schema_contract(&p_name).to_string();
                context.add_field(doc, &p_name_contracted, value, is_set);
            }
            Self::List {
                collect, entries, ..
            } => {
                // We previously peeked a list entry and decided we needed to recurse deeper.
                // this is the time to pop it.
                let _elt = entries.next().unwrap();
                collect.push(value);
            }
            Self::Array(a) => {
                let mut index = None;
                std::mem::swap(&mut index, &mut a.entries.last_index);

                a.collect.push((index.unwrap(), value));
            }
        }
    }
}

#[inline(never)]
fn collect_array(mut elements: Vec<(Vec<usize>, Value)>) -> Value {
    elements.sort_by(|(i1, _), (i2, _)| i1.cmp(i2));

    let dimensions = elements[0].0.len();
    let mut collect: Vec<Vec<Value>> = Vec::with_capacity(dimensions);
    collect.resize_with(dimensions, || Vec::new());

    for (index, value) in elements {
        assert!(
            index.len() == dimensions,
            "array elemenet did not have expected amount of dimensions"
        );

        // match indexes
        for d in 0..dimensions {
            let expected = collect[d].len();
            if expected < index[d] {
                // any less significant dimension will need to be gathered up, provided anything was collected to begin with.
                for n in (d + 1..dimensions).rev() {
                    if collect[n].len() != 0 {
                        let mut x = Vec::new();
                        std::mem::swap(&mut x, &mut collect[n]);
                        collect[n - 1].push(Value::Array(x));
                    }
                }

                // Then, we need to add null values until we're at the expected index.
                // Note that we might have just incremented by one due to the collect.
                collect[d].resize(index[d], Value::Null);
            }
        }

        // add the value
        collect[dimensions - 1].push(value);
    }

    // Finally, gather up everything
    for d in (0..dimensions - 1).rev() {
        let x = collect.pop().unwrap();
        if x.len() != 0 {
            collect[d].push(Value::Array(x));
        }
    }

    Value::Array(collect.pop().unwrap())
}

wrapped_arc_blob!(
    "GetDocumentContext",
    GetDocumentContextBlob,
    GetDocumentContext<SyncStoreLayer>,
    defaults
);

#[inline(never)]
fn map_to_writer<W: Write>(
    writer: W,
    m: Map<String, Value>,
    pretty: bool,
) -> serde_json::Result<()> {
    if pretty {
        serde_json::to_writer_pretty(writer, &Value::Object(m))
    } else {
        serde_json::to_writer(writer, &Value::Object(m))
    }
}

#[inline(never)]
fn map_to_string(m: Map<String, Value>, pretty: bool) -> String {
    if pretty {
        serde_json::to_string_pretty(&Value::Object(m))
            .expect("expected serialization to be possible")
    } else {
        Value::Object(m).to_string()
    }
}

#[inline(never)]
fn unify_json_string(term: &Term, s: String) -> PrologResult<()> {
    term.unify(s)
}

fn print_document<C: QueryableContextType>(
    context: &Context<C>,
    stream: &mut WritablePrologStream,
    doc: Map<String, Value>,
    as_list: bool,
    minimized: bool,
    stream_started: &mut bool,
) -> PrologResult<()> {
    if as_list && *stream_started {
        context.try_or_die_generic(stream.write_all(b",\n"))?;
    }
    *stream_started = true;

    context.try_or_die_generic(map_to_writer(&mut *stream, doc, !minimized))?;

    if !as_list {
        context.try_or_die(stream.write_all(b"\n"))?;
    }

    context.try_or_die(stream.flush())?;

    Ok(())
}

use super::types::*;
predicates! {
    #[module("$doc")]
    semidet fn get_document_context(context, transaction_term, compress_term, unfold_term, minimized_term, context_term) {
        let schema_layer = transaction_schema_layer(context, transaction_term)?.unwrap();
        let instance_layer = transaction_instance_layer(context, transaction_term)?;
        let compress: bool = compress_term.get()?;
        let unfold: bool = unfold_term.get()?;
        let minimized: bool = minimized_term.get()?;

        let get_context = GetDocumentContext::new(&schema_layer, instance_layer, compress, unfold, minimized);

        context_term.unify(GetDocumentContextBlob(Arc::new(get_context)))
    }

    #[module("$doc")]
    semidet fn print_document_json(context, stream_term, get_context_term, doc_name_term) {
        let mut stream: WritablePrologStream = stream_term.get_ex()?;
        if !doc_name_term.is_string() && !doc_name_term.is_atom() {
            return fail();
        }

        let doc_context: GetDocumentContextBlob = get_context_term.get()?;
        let s: PrologText = doc_name_term.get()?;
        if let Some(result) = doc_context.get_document(&s) {
            context.try_or_die_generic(map_to_writer(&mut stream, result, !doc_context.minimized))?;
            context.try_or_die(stream.write_all(b"\n"))
        }
        else {
            fail()
        }
    }

    #[module("$doc")]
    semidet fn print_all_documents_json(context, stream_term, get_context_term, skip_term, count_term, as_list_term) {
        let mut stream: WritablePrologStream = stream_term.get_ex()?;

        let doc_context: GetDocumentContextBlob = get_context_term.get()?;
        if doc_context.layer.is_none() {
            return Ok(());
        }

        let mut types: Vec<u64> = match doc_context.unfold {
            true => doc_context.document_types.iter().cloned().collect(),
            false => doc_context.types.iter().cloned().collect()
        };
        types.sort();

        let mut skip: u64 = skip_term.get_ex()?;
        let mut count: Option<u64> = attempt_opt(count_term.get())?;
        let as_list: bool = as_list_term.get_ex()?;
        let mut started = false;

        for typ in types {
            for t in doc_context.layer().triples_o(typ) {
                if skip != 0 {
                    // skip
                    skip -= 1;
                    continue;
                }
                if let Some(count) = count.as_mut() {
                    if *count == 0 {
                        break;
                    }
                    *count -= 1;
                }

                if Some(t.predicate) != doc_context.rdf_type_id {
                    continue;
                }

                let map = doc_context.get_id_document(t.subject);
                print_document(context, &mut stream, map, as_list, doc_context.minimized, &mut started)?;

            }
        }

        Ok(())
    }

    #[module("$doc")]
    semidet fn par_print_all_documents_json(context, stream_term, get_context_term, skip_term, count_term, as_list_term) {
        let mut stream: WritablePrologStream = stream_term.get_ex()?;

        let doc_context: GetDocumentContextBlob = get_context_term.get()?;
        if doc_context.layer.is_none() {
            return Ok(());
        }

        let minimized = doc_context.minimized;
        let skip: u64 = skip_term.get_ex()?;
        let count: Option<u64> = attempt_opt(count_term.get())?;
        let as_list: bool = as_list_term.get_ex()?;

        // We either iterate over the document types, or iif unfold is false, we iterate over all types
        let mut types: Vec<u64> = match doc_context.unfold {
            true => doc_context.document_types.iter().cloned().collect(),
            false => doc_context.types.iter().cloned().collect()
        };
        types.sort();

        let (sender, receiver) = mpsc::channel();

        let iter = types.into_iter().skip(skip as usize);
        let iter = if let Some(count) = count {
            itertools::Either::Left(iter.take(count as usize))
        }
        else {
            itertools::Either::Right(iter)
        };

        rayon::spawn(move || {
            iter.flat_map(|typ| doc_context.layer().triples_o(typ).filter(|t|Some(t.predicate) == doc_context.rdf_type_id))
                .enumerate()
                .par_bridge()
                .try_for_each_with(sender, |sender, (ix, t)| {
                    let map = doc_context.get_id_document(t.subject);
                    sender.send((ix, map)) // failure will kill the task
                }).unwrap();
        });

        let mut started = false;

        let mut result = BinaryHeap::new();
        let mut cur = 0;
        while let Ok((ix,map)) = receiver.recv() {
            if ix == cur {
                print_document(context, &mut stream, map, as_list, minimized, &mut started)?;

                cur += 1;
                while result.peek().map(|HeapEntry {index,..}|index == &cur).unwrap_or(false) {
                    let HeapEntry {index: _index, value } = result.pop().unwrap();

                    print_document(context, &mut stream, value, as_list, minimized, &mut started)?;

                    cur += 1;
                }
            }
            else {
                result.push(HeapEntry { index: ix, value: map });
            }
        }

        assert!(result.is_empty());

        Ok(())
    }
}

struct HeapEntry {
    index: usize,
    value: Map<String, Value>,
}

impl PartialEq for HeapEntry {
    fn eq(&self, other: &Self) -> bool {
        self.index == other.index
    }
}

impl Eq for HeapEntry {}

impl PartialOrd for HeapEntry {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.index.cmp(&other.index).reverse())
    }
}

impl Ord for HeapEntry {
    fn cmp(&self, other: &Self) -> Ordering {
        self.index.cmp(&other.index).reverse()
    }
}

pub fn register() {
    register_get_document_context();
    register_print_document_json();
    register_print_all_documents_json();
    register_par_print_all_documents_json();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn single_dim_array() {
        let collected = vec![
            (vec![0], Value::Bool(true)),
            (vec![1], Value::Bool(false)),
            (vec![2], Value::Bool(true)),
        ];

        let json = collect_array(collected);
        assert_eq!(
            Value::Array(vec![
                Value::Bool(true),
                Value::Bool(false),
                Value::Bool(true),
            ]),
            json
        );
    }

    #[test]
    fn single_dim_array_start_offset() {
        let collected = vec![
            (vec![3], Value::Bool(true)),
            (vec![4], Value::Bool(false)),
            (vec![5], Value::Bool(true)),
        ];

        let json = collect_array(collected);
        assert_eq!(
            Value::Array(vec![
                Value::Null,
                Value::Null,
                Value::Null,
                Value::Bool(true),
                Value::Bool(false),
                Value::Bool(true),
            ]),
            json
        );
    }

    #[test]
    fn single_dim_array_holes() {
        let collected = vec![
            (vec![0], Value::Bool(true)),
            (vec![3], Value::Bool(false)),
            (vec![5], Value::Bool(true)),
        ];

        let json = collect_array(collected);
        assert_eq!(
            Value::Array(vec![
                Value::Bool(true),
                Value::Null,
                Value::Null,
                Value::Bool(false),
                Value::Null,
                Value::Bool(true),
            ]),
            json
        );
    }

    #[test]
    fn double_dim_array() {
        let collected = vec![
            (vec![0, 0], Value::Bool(true)),
            (vec![0, 1], Value::Bool(false)),
            (vec![0, 2], Value::Bool(true)),
            (vec![1, 0], Value::Bool(false)),
            (vec![1, 1], Value::Bool(true)),
            (vec![1, 2], Value::Bool(false)),
        ];

        let json = collect_array(collected);
        assert_eq!(
            Value::Array(vec![
                Value::Array(vec![
                    Value::Bool(true),
                    Value::Bool(false),
                    Value::Bool(true),
                ]),
                Value::Array(vec![
                    Value::Bool(false),
                    Value::Bool(true),
                    Value::Bool(false)
                ])
            ]),
            json
        );
    }

    #[test]
    fn double_dim_array_offset() {
        let collected = vec![
            (vec![2, 3], Value::Bool(true)),
            (vec![2, 4], Value::Bool(false)),
            (vec![2, 5], Value::Bool(true)),
            (vec![3, 1], Value::Bool(false)),
            (vec![3, 2], Value::Bool(true)),
            (vec![3, 3], Value::Bool(false)),
        ];

        let json = collect_array(collected);
        assert_eq!(
            Value::Array(vec![
                Value::Null,
                Value::Null,
                Value::Array(vec![
                    Value::Null,
                    Value::Null,
                    Value::Null,
                    Value::Bool(true),
                    Value::Bool(false),
                    Value::Bool(true),
                ]),
                Value::Array(vec![
                    Value::Null,
                    Value::Bool(false),
                    Value::Bool(true),
                    Value::Bool(false)
                ])
            ]),
            json
        );
    }

    #[test]
    fn double_dim_array_holes() {
        let collected = vec![
            (vec![0, 0], Value::Bool(true)),
            (vec![0, 3], Value::Bool(false)),
            (vec![0, 5], Value::Bool(true)),
            (vec![3, 0], Value::Bool(false)),
            (vec![3, 2], Value::Bool(true)),
            (vec![3, 4], Value::Bool(false)),
            (vec![6, 0], Value::Bool(true)),
        ];

        let json = collect_array(collected);
        assert_eq!(
            Value::Array(vec![
                Value::Array(vec![
                    Value::Bool(true),
                    Value::Null,
                    Value::Null,
                    Value::Bool(false),
                    Value::Null,
                    Value::Bool(true),
                ]),
                Value::Null,
                Value::Null,
                Value::Array(vec![
                    Value::Bool(false),
                    Value::Null,
                    Value::Bool(true),
                    Value::Null,
                    Value::Bool(false),
                ]),
                Value::Null,
                Value::Null,
                Value::Array(vec![Value::Bool(true),]),
            ]),
            json
        );
    }
}
