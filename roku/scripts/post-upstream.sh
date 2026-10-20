#!/bin/bash
# Post to upstream's GitHub Discussions (chadMueller/Nostalgex) as the gh
# account that runs it, and print the new post's link. The only repo it can
# reach is upstream, and the only thing it can do is add a discussion or a
# comment, so a session can be allowed this script without being allowed gh.
#
#   scripts/post-upstream.sh new "<title>" <body.md>   new discussion (Ideas, else General)
#   scripts/post-upstream.sh comment <number> <body.md> comment on discussion <number>
#
# Record what was posted in docs/UPSTREAM.md.
set -euo pipefail
owner=chadMueller repo=Nostalgex
usage() { sed -n '7,8p' "$0" >&2; exit 2; }
[ $# -eq 3 ] || usage
[ -s "$3" ] || { echo "$3: empty or missing" >&2; exit 1; }
body=$(cat "$3")

case "$1" in
new)
    read -r repo_id cat_id < <(gh api graphql -f o="$owner" -f n="$repo" \
        -f query='query($o:String!,$n:String!){repository(owner:$o,name:$n){id discussionCategories(first:25){nodes{id name}}}}' \
        --jq '.data.repository as $r | ([$r.discussionCategories.nodes[] | select(.name=="Ideas")] + [$r.discussionCategories.nodes[] | select(.name=="General")])[0].id as $c | "\($r.id) \($c)"')
    [ -n "${cat_id:-}" ] && [ "$cat_id" != null ] || { echo "no Ideas or General category" >&2; exit 1; }
    gh api graphql -f r="$repo_id" -f c="$cat_id" -f t="$2" -f b="$body" \
        -f query='mutation($r:ID!,$c:ID!,$t:String!,$b:String!){createDiscussion(input:{repositoryId:$r,categoryId:$c,title:$t,body:$b}){discussion{url}}}' \
        --jq '.data.createDiscussion.discussion.url'
    ;;
comment)
    [[ "$2" =~ ^[0-9]+$ ]] || usage
    id=$(gh api graphql -f o="$owner" -f n="$repo" -F d="$2" \
        -f query='query($o:String!,$n:String!,$d:Int!){repository(owner:$o,name:$n){discussion(number:$d){id}}}' \
        --jq '.data.repository.discussion.id')
    gh api graphql -f i="$id" -f b="$body" \
        -f query='mutation($i:ID!,$b:String!){addDiscussionComment(input:{discussionId:$i,body:$b}){comment{url}}}' \
        --jq '.data.addDiscussionComment.comment.url'
    ;;
*) usage ;;
esac
