# 1. 停服、备份（略）

# 2. 依赖
pip3 install --user 'pymysql==0.10.1'

# 3. 预演（不写库）
cd d:\svn_debian8\mirage_skynet
python3 tools/merge_server.py --source-server 2 --target-server 1 --host 192.168.178.129 --port 3306 --user yaofan --password 123456 --dry-run

# 4. 正式合服
python3 tools/merge_server.py --source-server 2 --target-server 1 --host 192.168.178.129 --port 3306 --user yaofan --password 123456

# 5. 校验
mysql -h 192.168.178.129 -u yaofan -p123456 sk_s1_game < tools/merge_server_verify_game.sql
mysql -h 192.168.178.129 -u yaofan -p123456 sk_s1_global < tools/merge_server_verify_global.sql

# 6. 收尾
redis-cli -h 192.168.178.129 -a r12345 -p 6379 -n 1 FLUSHDB
# topology.yaml 注释掉 id:2 的 groups，重新 gen_config，只启 1 服进程