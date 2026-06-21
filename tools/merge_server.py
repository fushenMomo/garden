#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# requires python3.4+, pip3 install --user 'pymysql==0.10.1'

from __future__ import print_function

import argparse
import sys
import time

if sys.version_info[0] < 3:
    print("requires python3, run: python3 tools/merge_server.py ...", file=sys.stderr)
    sys.exit(1)

try:
    import pymysql
except ImportError:
    print("requires pymysql for python3.4: pip3 install --user 'pymysql==0.10.1'", file=sys.stderr)
    sys.exit(1)

DBID_BASE = 10518
ACT_BASE = 1018168
GUILD_ID_BASE = 1018
TABLE_INDEX_BASE = 1
ROLE_SHARDING = 500 * 10000
BAG_SHARDING = 30 * 10000
PLAYER_SHARDING = 500 * 10000
ROLE_SLOTS = ("role_1", "role_2", "role_3", "role_4")
ROLE_TABLES = ("role_base", "role_data", "role_guild")
GAME_SHARD_BASES = ("player_data", "role_base", "role_data", "role_guild", "bag_slots")


def calc_suffix(sharding, shard_key, id_base):
    if not shard_key or shard_key < id_base:
        return TABLE_INDEX_BASE
    return (shard_key - id_base) // sharding + TABLE_INDEX_BASE


def shard_table(base, suffix):
    return "{0}_{1}".format(base, suffix)


def qident(name):
    return "`" + name.replace("`", "``") + "`"


def esc(val):
    if val is None:
        return "NULL"
    if isinstance(val, (int, float)):
        return str(int(val))
    s = str(val).replace("\\", "\\\\").replace("'", "\\'")
    return "'{0}'".format(s)


class MergeContext(object):
    def __init__(self, args):
        self.args = args
        self.source = args.source_server
        self.target = args.target_server
        self.gap = args.gap
        self.dry_run = args.dry_run
        self.now = int(time.time())
        self.dbid_map = {}
        self.guild_map = {}
        self.job_map = {}
        self.dbid_offset = 0
        self.guild_offset = 0
        self.job_offset = 0
        self.stats = {}
        self.role_names = set()
        self.guild_names = set()
        self._conns = {}

    def db(self, name):
        if name not in self._conns:
            self._conns[name] = pymysql.connect(
                host=self.args.host,
                port=self.args.port,
                user=self.args.user,
                password=self.args.password,
                database=name,
                charset="utf8mb4",
                autocommit=False,
            )
        return self._conns[name]

    def game_db(self, server_id):
        return self.db("sk_s{0}_game".format(server_id))

    def global_db(self, server_id):
        return self.db("sk_s{0}_global".format(server_id))

    def login_db(self):
        return self.db(self.args.login_db)

    def close(self):
        for c in self._conns.values():
            c.close()

    def execute(self, conn, sql):
        with conn.cursor() as cur:
            cur.execute(sql)
            if cur.description:
                cols = [d[0] for d in cur.description]
                return [dict(zip(cols, row)) for row in cur.fetchall()]
            return []

    def execute_one(self, conn, sql):
        rows = self.execute(conn, sql)
        return rows[0] if rows else None

    def inc(self, key, n=1):
        self.stats[key] = self.stats.get(key, 0) + n

    def list_shard_tables(self, conn, base):
        with conn.cursor() as cur:
            cur.execute("SHOW TABLES LIKE %s", (base + "_%",))
            rows = cur.fetchall()
        names = sorted(r[0] for r in rows)
        if not names:
            names = [shard_table(base, TABLE_INDEX_BASE)]
        return names

    def load_existing_names(self):
        tgt = self.global_db(self.target)
        game_tgt = self.game_db(self.target)
        for tbl in self.list_shard_tables(game_tgt, "role_base"):
            sql = "SELECT name FROM {0}".format(qident(tbl))
            for row in self.execute(game_tgt, sql):
                self.role_names.add(row["name"])
        for row in self.execute(tgt, "SELECT name FROM guild_data"):
            self.guild_names.add(row["name"])

    def get_role_table_index(self, server_id):
        conn = self.global_db(server_id)
        row = self.execute_one(conn, "SELECT role_table_index FROM game_global WHERE idx=1")
        if row and row.get("role_table_index"):
            return int(row["role_table_index"])
        return TABLE_INDEX_BASE

    def max_dbid(self, server_id):
        idx = self.get_role_table_index(server_id)
        conn = self.game_db(server_id)
        mx = 0
        for i in range(TABLE_INDEX_BASE, idx + 1):
            tbl = shard_table("role_base", i)
            sql = "SELECT MAX(dbid) AS m FROM {0}".format(qident(tbl))
            row = self.execute_one(conn, sql)
            if row and row.get("m"):
                mx = max(mx, int(row["m"]))
        return mx

    def calc_offsets(self):
        tgt_g = self.global_db(self.target)
        max_dbid = self.max_dbid(self.target)
        row_g = self.execute_one(tgt_g, "SELECT MAX(guild_id) AS m FROM guild_data")
        row_j = self.execute_one(tgt_g, "SELECT MAX(id) AS m FROM pending_job")
        max_guild = int(row_g["m"]) if row_g and row_g.get("m") else (GUILD_ID_BASE - 1)
        max_job = int(row_j["m"]) if row_j and row_j.get("m") else 0
        self.dbid_offset = max_dbid + self.gap
        self.guild_offset = max_guild + self.gap
        self.job_offset = max_job + self.gap
        print("offset dbid={0} guild={1} job={2}".format(
            self.dbid_offset, self.guild_offset, self.job_offset))

    def build_id_maps(self):
        src_game = self.game_db(self.source)
        src_global = self.global_db(self.source)
        for tbl in self.list_shard_tables(src_game, "role_base"):
            sql = "SELECT dbid FROM {0}".format(qident(tbl))
            for row in self.execute(src_game, sql):
                old = int(row["dbid"])
                if old < DBID_BASE:
                    print("WARN skip abnormal dbid={0}".format(old))
                    continue
                new = old + self.dbid_offset
                self.dbid_map[old] = new
        for row in self.execute(src_global, "SELECT guild_id FROM guild_data"):
            old = int(row["guild_id"])
            if old < GUILD_ID_BASE:
                print("WARN skip abnormal guild_id={0}".format(old))
                continue
            self.guild_map[old] = old + self.guild_offset
        for row in self.execute(src_global, "SELECT id FROM pending_job"):
            old = int(row["id"])
            self.job_map[old] = old + self.job_offset
        print("maps dbid={0} guild={1} job={2}".format(
            len(self.dbid_map), len(self.guild_map), len(self.job_map)))

    def ensure_shard(self, conn, base, suffix):
        if self.dry_run:
            return
        tgt = shard_table(base, suffix)
        base_tbl = shard_table(base, TABLE_INDEX_BASE)
        if tgt == base_tbl:
            return
        sql = "CREATE TABLE IF NOT EXISTS {0} LIKE {1}".format(qident(tgt), qident(base_tbl))
        self.execute(conn, sql)

    def ensure_shards_for_dbid(self, conn, dbid):
        for base, sharding in (("role_base", ROLE_SHARDING), ("role_data", ROLE_SHARDING),
                               ("role_guild", ROLE_SHARDING), ("bag_slots", BAG_SHARDING)):
            sfx = calc_suffix(sharding, dbid, DBID_BASE)
            self.ensure_shard(conn, base, sfx)

    def resolve_role_name(self, name, new_dbid):
        if name not in self.role_names:
            self.role_names.add(name)
            return name
        suffix = "_{0}".format(self.source)
        new_name = name[: 32 - len(suffix)] + suffix
        if new_name in self.role_names:
            i = 1
            while True:
                suffix2 = "_{0}_{1}".format(self.source, i)
                new_name = name[: 32 - len(suffix2)] + suffix2
                if new_name not in self.role_names:
                    break
                i += 1
        self.role_names.add(new_name)
        return new_name

    def resolve_guild_name(self, name, new_guild_id):
        if name not in self.guild_names:
            self.guild_names.add(name)
            return name
        suffix = "_{0}".format(self.source)
        new_name = name[: 20 - len(suffix)] + suffix
        if new_name in self.guild_names:
            i = 1
            while True:
                suffix2 = "_{0}_{1}".format(self.source, i)
                new_name = name[: 20 - len(suffix2)] + suffix2
                if new_name not in self.guild_names:
                    break
                i += 1
        self.guild_names.add(new_name)
        return new_name

    def record_id_map(self, conn):
        if self.dry_run:
            return
        for id_type, mapping in (("dbid", self.dbid_map), ("guild_id", self.guild_map), ("job_id", self.job_map)):
            for old_id, new_id in mapping.items():
                sql = (
                    "INSERT INTO merge_id_map (src_server_id,id_type,old_id,new_id,merge_time) "
                    "VALUES ({0},{1},{2},{3},{4})"
                ).format(self.source, esc(id_type), old_id, new_id, self.now)
                self.execute(conn, sql)

    def record_rename(self, conn, entity_type, old_name, new_name, entity_id):
        if self.dry_run or old_name == new_name:
            return
        sql = (
            "INSERT INTO merge_rename_log (src_server_id,entity_type,old_name,new_name,entity_id,merge_time) "
            "VALUES ({0},{1},{2},{3},{4},{5})"
        ).format(self.source, esc(entity_type), esc(old_name), esc(new_name), entity_id, self.now)
        self.execute(conn, sql)

    def record_overflow(self, conn, act_id, old_dbid, new_dbid):
        if self.dry_run:
            return
        sql = (
            "INSERT INTO merge_overflow_roles (src_server_id,act_id,old_dbid,new_dbid,merge_time) "
            "VALUES ({0},{1},{2},{3},{4})"
        ).format(self.source, act_id, old_dbid, new_dbid, self.now)
        self.execute(conn, sql)

    def map_dbid(self, val):
        if not val:
            return 0
        val = int(val)
        return self.dbid_map.get(val, val)

    def map_guild(self, val):
        if not val:
            return 0
        val = int(val)
        return self.guild_map.get(val, val)

    def map_job(self, val):
        if not val:
            return 0
        val = int(val)
        return self.job_map.get(val, val)

    def migrate_role_base(self):
        src = self.game_db(self.source)
        tgt = self.game_db(self.target)
        tgt_g = self.global_db(self.target)
        for tbl in self.list_shard_tables(src, "role_base"):
            sql = "SELECT * FROM {0}".format(qident(tbl))
            for row in self.execute(src, sql):
                old_dbid = int(row["dbid"])
                if old_dbid not in self.dbid_map:
                    continue
                new_dbid = self.dbid_map[old_dbid]
                self.ensure_shards_for_dbid(tgt, new_dbid)
                tgt_tbl = shard_table("role_base", calc_suffix(ROLE_SHARDING, new_dbid, DBID_BASE))
                old_name = row["name"]
                new_name = self.resolve_role_name(old_name, new_dbid)
                self.record_rename(tgt_g, "role", old_name, new_name, new_dbid)
                sql = (
                    "INSERT INTO {0} "
                    "(dbid,act_id,server_id,name,create_time,sex) VALUES ("
                    "{1},{2},{3},{4},{5},{6})"
                ).format(
                    qident(tgt_tbl), new_dbid, row["act_id"], self.target, esc(new_name),
                    row["create_time"], row["sex"])
                if not self.dry_run:
                    self.execute(tgt, sql)
                self.inc("role_base")

    def migrate_role_data(self):
        src = self.game_db(self.source)
        tgt = self.game_db(self.target)
        for tbl in self.list_shard_tables(src, "role_data"):
            sql = "SELECT * FROM {0}".format(qident(tbl))
            for row in self.execute(src, sql):
                old = int(row["parent_dbid"])
                if old not in self.dbid_map:
                    continue
                new = self.dbid_map[old]
                tgt_tbl = shard_table("role_data", calc_suffix(ROLE_SHARDING, new, DBID_BASE))
                sql = (
                    "INSERT INTO {0} "
                    "(parent_dbid,move_speed,team_level,team_exp,fighting_value,"
                    "school_level,school_exp,military_lv) VALUES ("
                    "{1},{2},{3},{4},{5},{6},{7},{8})"
                ).format(
                    qident(tgt_tbl), new, row["move_speed"], row["team_level"], row["team_exp"],
                    row["fighting_value"], row["school_level"], row["school_exp"], row["military_lv"])
                if not self.dry_run:
                    self.execute(tgt, sql)
                self.inc("role_data")

    def migrate_role_guild(self):
        src = self.game_db(self.source)
        tgt = self.game_db(self.target)
        for tbl in self.list_shard_tables(src, "role_guild"):
            sql = "SELECT * FROM {0}".format(qident(tbl))
            for row in self.execute(src, sql):
                old = int(row["parent_dbid"])
                if old not in self.dbid_map:
                    continue
                new = self.dbid_map[old]
                tgt_tbl = shard_table("role_guild", calc_suffix(ROLE_SHARDING, new, DBID_BASE))
                gid = self.map_guild(row["guild_id"])
                last_gid = self.map_guild(row["last_guild_id"])
                req = row.get("req_list")
                sql = (
                    "INSERT INTO {0} "
                    "(parent_dbid,guild_id,exit_cd,req_list,guild_title,last_guild_id) VALUES ("
                    "{1},{2},{3},{4},{5},{6})"
                ).format(qident(tgt_tbl), new, gid, row["exit_cd"], esc(req), row["guild_title"], last_gid)
                if not self.dry_run:
                    self.execute(tgt, sql)
                self.inc("role_guild")

    def migrate_bag_slots(self):
        src = self.game_db(self.source)
        tgt = self.game_db(self.target)
        for tbl in self.list_shard_tables(src, "bag_slots"):
            sql = "SELECT * FROM {0}".format(qident(tbl))
            for row in self.execute(src, sql):
                old = int(row["parent_dbid"])
                if old not in self.dbid_map:
                    continue
                new = self.dbid_map[old]
                tgt_tbl = shard_table("bag_slots", calc_suffix(BAG_SHARDING, new, DBID_BASE))
                g1 = self.map_dbid(row["guid_1"]) if row["guid_1"] in self.dbid_map else row["guid_1"]
                sql = (
                    "INSERT INTO {0} "
                    "(parent_dbid,item_index,guid_1,guid_2,item_id,count,data) VALUES ("
                    "{1},{2},{3},{4},{5},{6},{7})"
                ).format(
                    qident(tgt_tbl), new, row["item_index"], g1, row["guid_2"],
                    row["item_id"], row["count"], esc(row.get("data")))
                if not self.dry_run:
                    self.execute(tgt, sql)
                self.inc("bag_slots")

    def find_player(self, conn, server_id, act_id):
        sfx = calc_suffix(PLAYER_SHARDING, act_id, ACT_BASE)
        tbl = shard_table("player_data", sfx)
        self.ensure_shard(conn, "player_data", sfx)
        sql = "SELECT * FROM {0} WHERE act_id={1} AND server_id={2}".format(qident(tbl), act_id, server_id)
        return self.execute_one(conn, sql)

    def upsert_player(self, conn, act_id, row, action):
        sfx = calc_suffix(PLAYER_SHARDING, act_id, ACT_BASE)
        tbl = shard_table("player_data", sfx)
        self.ensure_shard(conn, "player_data", sfx)
        if action == "insert":
            sql = (
                "INSERT INTO {0} "
                "(act_id,server_id,online,online_time,select_role,role_1,role_2,role_3,role_4,"
                "shutup,create_time) VALUES ("
                "{1},{2},0,{3},{4},{5},{6},{7},{8},{9},{10})"
            ).format(
                qident(tbl), row["act_id"], row["server_id"], row["online_time"],
                row["select_role"], row["role_1"], row["role_2"], row["role_3"],
                row["role_4"], row["shutup"], row["create_time"])
        else:
            sql = (
                "UPDATE {0} SET "
                "online_time={1},select_role={2},"
                "role_1={3},role_2={4},role_3={5},"
                "role_4={6},shutup={7} "
                "WHERE act_id={8} AND server_id={9}"
            ).format(
                qident(tbl), row["online_time"], row["select_role"],
                row["role_1"], row["role_2"], row["role_3"], row["role_4"],
                row["shutup"], row["act_id"], row["server_id"])
        if not self.dry_run:
            self.execute(conn, sql)

    def migrate_player_data(self):
        src = self.game_db(self.source)
        tgt = self.game_db(self.target)
        tgt_g = self.global_db(self.target)
        seen = set()
        for tbl in self.list_shard_tables(src, "player_data"):
            sql = "SELECT * FROM {0}".format(qident(tbl))
            for row in self.execute(src, sql):
                act_id = int(row["act_id"])
                if int(row["server_id"]) != self.source:
                    continue
                if act_id in seen:
                    continue
                seen.add(act_id)
                src_roles = [self.map_dbid(row[s]) for s in ROLE_SLOTS]
                src_row = dict(row)
                src_row["server_id"] = self.target
                src_row["select_role"] = self.map_dbid(row["select_role"])
                for i, s in enumerate(ROLE_SLOTS):
                    src_row[s] = src_roles[i]
                tgt_row = self.find_player(tgt, self.target, act_id)
                if not tgt_row:
                    if not self.dry_run:
                        self.upsert_player(tgt, act_id, src_row, "insert")
                    self.inc("player_insert")
                    continue
                merged = dict(tgt_row)
                free = [s for s in ROLE_SLOTS if not int(merged[s])]
                overflow = []
                for r in src_roles:
                    if not r:
                        continue
                    if free:
                        merged[free.pop(0)] = r
                    else:
                        overflow.append(r)
                if not self.dry_run:
                    self.upsert_player(tgt, act_id, merged, "update")
                self.inc("player_merge")
                for new_dbid in overflow:
                    old_dbid = next((k for k, v in self.dbid_map.items() if v == new_dbid), new_dbid)
                    self.record_overflow(tgt_g, act_id, old_dbid, new_dbid)
                    self.inc("player_overflow")

    def migrate_guild_data(self):
        src = self.global_db(self.source)
        tgt = self.global_db(self.target)
        for row in self.execute(src, "SELECT * FROM guild_data"):
            old = int(row["guild_id"])
            if old not in self.guild_map:
                continue
            new = self.guild_map[old]
            old_name = row["name"]
            new_name = self.resolve_guild_name(old_name, new)
            self.record_rename(tgt, "guild", old_name, new_name, new)
            sql = (
                "INSERT INTO guild_data "
                "(guild_id,name,brief,head_id,member_count,level,exp,create_time,"
                "approval_status,req_list,rename_times) VALUES ("
                "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10})"
            ).format(
                new, esc(new_name), esc(row["brief"]), row["head_id"],
                row["member_count"], row["level"], row["exp"], row["create_time"],
                row["approval_status"], esc(row.get("req_list")), row["rename_times"])
            if not self.dry_run:
                self.execute(tgt, sql)
            self.inc("guild_data")

    def migrate_guild_member(self):
        src = self.global_db(self.source)
        tgt = self.global_db(self.target)
        for row in self.execute(src, "SELECT * FROM guild_member"):
            old_g = int(row["guild_id"])
            if old_g not in self.guild_map:
                continue
            new_g = self.guild_map[old_g]
            role_dbid = self.map_dbid(row["role_dbid"])
            sql = (
                "INSERT INTO guild_member "
                "(guild_id,`index`,role_dbid,sex,standing,name,fighting_value,logout_time,join_time) "
                "VALUES ({0},{1},{2},{3},{4},{5},{6},{7},{8})"
            ).format(
                new_g, row["index"], role_dbid, row["sex"], row["standing"],
                esc(row["name"]), row["fighting_value"], row["logout_time"], row["join_time"])
            if not self.dry_run:
                self.execute(tgt, sql)
            self.inc("guild_member")

    def migrate_pending_job(self):
        src = self.global_db(self.source)
        tgt = self.global_db(self.target)
        for table in ("pending_job", "pending_job_log"):
            sql = "SELECT * FROM {0}".format(table)
            for row in self.execute(src, sql):
                old_id = int(row["id"])
                new_id = self.map_job(old_id)
                parent = self.map_dbid(row["parent_dbid"])
                sql = (
                    "INSERT INTO {0} "
                    "(id,parent_dbid,status,create_time,finish_time,job_data) VALUES ("
                    "{1},{2},{3},{4},{5},{6})"
                ).format(
                    table, new_id, parent, row["status"], row["create_time"],
                    row["finish_time"], esc(row.get("job_data")))
                if not self.dry_run:
                    self.execute(tgt, sql)
                self.inc(table)

    def merge_game_global(self):
        src = self.global_db(self.source)
        tgt = self.global_db(self.target)
        s = self.execute_one(src, "SELECT * FROM game_global WHERE idx=1") or {}
        t = self.execute_one(tgt, "SELECT * FROM game_global WHERE idx=1") or {}
        merged_idx = max(int(s.get("role_table_index") or 1), int(t.get("role_table_index") or 1))
        merged_start = min(
            int(s.get("server_start_time") or 0) or 4294967295,
            int(t.get("server_start_time") or 0) or 4294967295,
        )
        if merged_start == 4294967295:
            merged_start = 0
        sql = (
            "UPDATE game_global SET "
            "role_table_index={0},"
            "server_start_time={1},"
            "last_0am_update=GREATEST({2},{3}),"
            "last_6am_update=GREATEST({4},{5}) "
            "WHERE idx=1"
        ).format(
            merged_idx, merged_start,
            int(t.get("last_0am_update") or 0), int(s.get("last_0am_update") or 0),
            int(t.get("last_6am_update") or 0), int(s.get("last_6am_update") or 0))
        if not self.dry_run:
            self.execute(tgt, sql)

    def update_login(self):
        conn = self.login_db()
        if not self.dry_run:
            self.execute(
                conn,
                "UPDATE login_info SET last_server_id={0} WHERE last_server_id={1}".format(
                    self.target, self.source),
            )
            self.execute(
                conn,
                "UPDATE server_list SET state=0, `show`=0 WHERE id={0}".format(self.source),
            )
        self.inc("login_update")

    def fix_auto_increment(self):
        tgt_game = self.game_db(self.target)
        tgt_g = self.global_db(self.target)
        max_dbid = self.max_dbid(self.target)
        if max_dbid >= DBID_BASE:
            sfx = calc_suffix(ROLE_SHARDING, max_dbid, DBID_BASE)
            tbl = shard_table("role_base", sfx)
            if not self.dry_run:
                sql = "ALTER TABLE {0} AUTO_INCREMENT={1}".format(qident(tbl), max_dbid + 1)
                self.execute(tgt_game, sql)
        row_g = self.execute_one(tgt_g, "SELECT MAX(guild_id) AS m FROM guild_data")
        row_j = self.execute_one(tgt_g, "SELECT MAX(id) AS m FROM pending_job")
        max_guild = int(row_g["m"]) if row_g and row_g.get("m") else GUILD_ID_BASE
        max_job = int(row_j["m"]) if row_j and row_j.get("m") else 1
        if not self.dry_run:
            self.execute(tgt_g, "ALTER TABLE guild_data AUTO_INCREMENT={0}".format(max_guild + 1))
            self.execute(tgt_g, "ALTER TABLE pending_job AUTO_INCREMENT={0}".format(max_job + 1))

    def init_audit_tables(self):
        tgt_g = self.global_db(self.target)
        ddl_path = self.args.audit_ddl
        with open(ddl_path, "r") as f:
            sql_text = f.read()
        if not self.dry_run:
            for stmt in sql_text.split(";"):
                stmt = stmt.strip()
                if stmt:
                    self.execute(tgt_g, stmt)

    def run(self):
        print("merge source={0} -> target={1} dry_run={2}".format(
            self.source, self.target, self.dry_run))
        self.calc_offsets()
        self.build_id_maps()
        self.load_existing_names()
        if not self.dry_run:
            self.init_audit_tables()
        self.migrate_role_base()
        self.migrate_role_data()
        self.migrate_role_guild()
        self.migrate_bag_slots()
        self.migrate_player_data()
        self.migrate_guild_data()
        self.migrate_guild_member()
        self.migrate_pending_job()
        self.merge_game_global()
        self.record_id_map(self.global_db(self.target))
        self.update_login()
        self.fix_auto_increment()
        if not self.dry_run:
            for c in self._conns.values():
                c.commit()
        print("stats:", self.stats)
        if not self.dry_run:
            print("post: FLUSHDB target Redis; remove source groups in topology.yaml then gen_config")


def main():
    p = argparse.ArgumentParser(description="mirage_skynet offline server merge")
    p.add_argument("--source-server", type=int, required=True)
    p.add_argument("--target-server", type=int, required=True)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=3306)
    p.add_argument("--user", default="root")
    p.add_argument("--password", default="")
    p.add_argument("--login-db", default="sk_login")
    p.add_argument("--gap", type=int, default=10000)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument(
        "--audit-ddl",
        default="data/global/merge_server.sql",
        help="audit table DDL path",
    )
    args = p.parse_args()
    if args.source_server == args.target_server:
        print("source-server and target-server must differ", file=sys.stderr)
        sys.exit(1)
    ctx = MergeContext(args)
    try:
        ctx.run()
    except Exception:
        for c in ctx._conns.values():
            c.rollback()
        raise
    finally:
        ctx.close()


if __name__ == "__main__":
    main()
