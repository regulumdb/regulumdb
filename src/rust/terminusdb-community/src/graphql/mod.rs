use juniper::{http::GraphQLRequest, EmptyMutation, EmptySubscription, RootNode};

use std::io::Read;
use std::sync::Arc;
use swipl::prelude::*;

mod filter;
pub mod frame;
pub mod query;
mod sanitize;
mod schema;
mod top;

use self::{
    frame::AllFrames,
    schema::{TerminusContext, TerminusTypeCollection, TerminusTypeCollectionInfo},
};

predicates! {
    #[module("$graphql")]
    semidet fn handle_request(context, _method_term, frame_term, system_term, meta_term, commit_term, transaction_term, auth_term, content_length_term, input_stream_term, response_term) {
        let mut input: ReadablePrologStream = input_stream_term.get_ex()?;
        let len = content_length_term.get_ex::<u64>()? as usize;
        let mut buf = vec![0;len];
        context.try_or_die_generic(input.read_exact(&mut buf))?;

        let request;
        match serde_json::from_slice::<GraphQLRequest>(&buf) {
            Ok(r) => {
                log_debug!(context, "request: {:?}", r)?;
                request = r;
            },
            Err(error) => return context.raise_exception(&term!{context: error(json_parse_error(#error.line() as u64, #error.column() as u64), _)}?)
        }

        let frames: AllFrames = context.deserialize_from_term(&frame_term).expect("Unable to parse frames into rust struct");
        let mut sanitized_frames: AllFrames = frames.sanitize();
        sanitized_frames.invert();
        sanitized_frames.calculate_subsumption();
        eprintln!("sanitized: {sanitized_frames:?}");
        let root_node = RootNode::new_with_info(TerminusTypeCollection::new(),
                                                EmptyMutation::<TerminusContext<'a, C>>::new(),
                                                EmptySubscription::<TerminusContext<'a,C>>::new(),
                                                TerminusTypeCollectionInfo{ allframes: Arc::new(sanitized_frames)}, (), ());

        let graphql_context = TerminusContext::new(context, auth_term, system_term, meta_term, commit_term,transaction_term)?;
        //let graphql_context = Info::new(context, system_term, meta_term, commit_term, branch_term, transaction_term, auth_term)?;

        let response = request.execute_sync(&root_node, &graphql_context);

        log_debug!(context, "graphql response: {:?}", response)?;

        match serde_json::to_string(&response){
            Ok(r) => response_term.unify(r),
            Err(_) => return context.raise_exception(&term!{context: error(json_serialize_error, _)}?),
        }
    }
}

pub fn register() {
    register_handle_request();
}
