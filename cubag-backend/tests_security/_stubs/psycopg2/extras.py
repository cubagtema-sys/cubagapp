class RealDictCursor:
    pass


class RealDictRow(dict):
    pass


def execute_values(cur, sql, argslist, *a, **k):
    for args in argslist:
        cur.execute(sql, args)
