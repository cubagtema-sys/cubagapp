from fakedb import FakeConnection


class ThreadedConnectionPool:
    def __init__(self, *a, **k):
        pass

    def getconn(self):
        return FakeConnection()

    def putconn(self, conn, close=False):
        pass
