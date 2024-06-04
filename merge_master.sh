git switch master
git diff master dev --name-only |
grep -v 'Dockerfile' |
grep -v 'Gemfile.lock' |
grep -v '_plugins/external-posts.rb' |
grep -v 'bin/entry_point.sh' |
grep -v 'docker-compose.yml' |
grep -v 'feed.xml' |
grep -v 'merge_master.sh' |
sed 's/.*/"&"/' |
xargs git checkout dev