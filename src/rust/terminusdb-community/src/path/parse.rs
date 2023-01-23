use nom::bytes::complete::{tag, take_while, take_while1};
use nom::multi::separated_list1;
use nom::sequence::preceded;
use nom::{
    branch::alt,
    combinator::{map, map_res},
    error::ErrorKind,
    sequence::{delimited, pair, separated_pair, terminated},
    IResult,
};
use std::rc::Rc;

/*

P := '.' | String
Q,R := P> | <P | Q,R | Q;R | Q+ | Q* | Q{N,M} | P@T

 */

#[derive(Debug, PartialEq, Clone)]
pub enum Pred {
    Any,
    Named(String),
}

#[derive(Debug, PartialEq, Clone)]
pub enum Path {
    Seq(Vec<Path>),
    Choice(Vec<Path>),
    Positive(Pred),
    Negative(Pred),
    Plus(Rc<Path>),
    Star(Rc<Path>),
    Times(Rc<Path>, usize, usize),
}

fn is_property_char(c: char) -> bool {
    c.is_alphanumeric() || c == ':' || c == '/' || c == '_' || c == '-'
}

fn named(input: &str) -> IResult<&str, &str> {
    take_while1(is_property_char)(input)
}

fn num(input: &str) -> IResult<&str, usize> {
    map_res(
        take_while(|c: char| c.is_ascii_digit()),
        |digits: &str| -> Result<usize, _> {
            Ok::<usize, ErrorKind>(digits.parse::<usize>().unwrap())
        },
    )(input)
}

fn pred(input: &str) -> IResult<&str, Pred> {
    alt((
        map(tag("."), |_| Pred::Any),
        map(named, |string| Pred::Named(string.to_string())),
    ))(input)
}

fn positive(input: &str) -> IResult<&str, Pred> {
    alt((terminated(pred, tag(">")), pred))(input)
}

fn negative(input: &str) -> IResult<&str, Pred> {
    preceded(tag("<"), pred)(input)
}

fn patterns(input: &str) -> IResult<&str, Path> {
    alt((
        delimited(tag("("), ands, tag(")")),
        map(negative, Path::Negative),
        map(positive, Path::Positive),
    ))(input)
}

fn plus(input: &str) -> IResult<&str, Path> {
    terminated(patterns, tag("+"))(input)
}

fn star(input: &str) -> IResult<&str, Path> {
    terminated(patterns, tag("*"))(input)
}

fn size_bracket(input: &str) -> IResult<&str, (usize, usize)> {
    delimited(tag("{"), separated_pair(num, tag(","), num), tag("}"))(input)
}

fn times(input: &str) -> IResult<&str, Path> {
    map(pair(patterns, size_bracket), |(p, (n, m))| {
        Path::Times(Rc::new(p), n, m)
    })(input)
}

fn repeat_patterns(input: &str) -> IResult<&str, Path> {
    alt((
        map(plus, |elt| Path::Plus(Rc::new(elt))),
        map(star, |elt| Path::Star(Rc::new(elt))),
        times,
        patterns,
    ))(input)
}

fn ors(input: &str) -> IResult<&str, Path> {
    alt((
        map(
            pair(
                terminated(repeat_patterns, tag("|")),
                separated_list1(tag("|"), repeat_patterns),
            ),
            |(first, paths)| {
                let mut result = paths;
                result.insert(0, first);
                Path::Choice(result)
            },
        ),
        repeat_patterns,
    ))(input)
}

fn ands(input: &str) -> IResult<&str, Path> {
    alt((
        map(
            pair(terminated(ors, tag(",")), separated_list1(tag(","), ors)),
            |(first, paths)| {
                let mut result = paths;
                result.insert(0, first);
                Path::Seq(result)
            },
        ),
        ors,
    ))(input)
}

pub fn parse_path(input: &str) -> IResult<&str, Path> {
    ands(input)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_pred() {
        let source = "rdf:first";
        let results = pred(source);
        assert_eq!(results, Ok(("", Pred::Named("rdf:first".to_string()))))
    }

    #[test]
    fn parse_cons_chaser() {
        let source = "p,rdf:rest*,rdf:first";
        let results = parse_path(source);
        assert_eq!(
            results,
            Ok((
                "",
                Path::Seq(vec![
                    Path::Positive(Pred::Named("p".to_string())),
                    Path::Star(Rc::new(Path::Positive(Pred::Named("rdf:rest".to_string())))),
                    Path::Positive(Pred::Named("rdf:first".to_string()))
                ])
            ))
        )
    }

    #[test]
    fn parse_backward_repeat_group() {
        let source = "(<effect,cause)+";
        let results = parse_path(source);
        assert_eq!(
            results,
            Ok((
                "",
                Path::Plus(Rc::new(Path::Seq(vec![
                    Path::Negative(Pred::Named("effect".to_string())),
                    Path::Positive(Pred::Named("cause".to_string()))
                ])))
            ))
        )
    }

    #[test]
    fn parse_any() {
        let source = ".";
        let results = parse_path(source);
        assert_eq!(results, Ok(("", Path::Positive(Pred::Any))))
    }

    #[test]
    fn parse_something() {
        let source = "(forward,.,<backward)+";
        let results = parse_path(source);
        assert_eq!(
            results,
            Ok((
                "",
                Path::Plus(Rc::new(Path::Seq(vec![
                    Path::Positive(Pred::Named("forward".to_string())),
                    Path::Positive(Pred::Any),
                    Path::Negative(Pred::Named("backward".to_string()))
                ])))
            ))
        )
    }

    #[test]
    fn repeated_choice() {
        let source = "(child|database)*";
        let results = parse_path(source);
        assert_eq!(
            results,
            Ok((
                "",
                Path::Star(Rc::new(Path::Choice(vec![
                    Path::Positive(Pred::Named("child".to_string())),
                    Path::Positive(Pred::Named("database".to_string()))
                ])))
            ))
        )
    }

    #[test]
    fn and_then_n_m() {
        let source = "first,(second,third){1,4}";
        let results = parse_path(source);
        assert_eq!(
            results,
            Ok((
                "",
                Path::Seq(vec![
                    Path::Positive(Pred::Named("first".to_string())),
                    Path::Times(
                        Rc::new(Path::Seq(vec![
                            Path::Positive(Pred::Named("second".to_string())),
                            Path::Positive(Pred::Named("third".to_string()))
                        ])),
                        1,
                        4
                    )
                ])
            ))
        )
    }
}
