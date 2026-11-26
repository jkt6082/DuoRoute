"""Minimal Lua table-literal reader. Parses data; never executes anything.

Supports: nil/true/false, numbers, strings (short and long), tables with
positional/named/[expr] keys, dotted/indexed name lookups resolved from a
provided dict, + - * / and unary minus, and l10n("x") style calls (returns
first argument).  Anything unknown resolves to None.
"""
import re

TOKEN_RE = re.compile(r'''
    (?P<ws>\s+)
  | (?P<lcomment>--\[(?P<leq>=*)\[.*?\](?P=leq)\])
  | (?P<comment>--[^\n]*)
  | (?P<lstr>\[(?P<seq>=*)\[.*?\](?P=seq)\])
  | (?P<num>0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)
  | (?P<str>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.|==|~=|<=|>=|[{}\[\]=,;.+\-*/()#:<>%^])
''', re.S | re.X)

ESC = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"', "'": "'", '\n': '\n', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v'}


def unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            if n.isdigit():
                m = re.match(r'\d{1,3}', s[i + 1:])
                out.append(chr(int(m.group(0))))
                i += 1 + len(m.group(0))
                continue
            out.append(ESC.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def tokenize(src):
    toks = []
    pos = 0
    n = len(src)
    while pos < n:
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise SyntaxError('bad char %r at %d' % (src[pos], pos))
        pos = m.end()
        k = m.lastgroup
        if k in ('ws', 'comment', 'lcomment'):
            continue
        v = m.group(k)
        if k == 'lstr':
            eq = m.group('seq')
            body = v[2 + len(eq):-(2 + len(eq))]
            if body.startswith('\n'):
                body = body[1:]
            toks.append(('str', body))
        elif k == 'str':
            toks.append(('str', unescape(v[1:-1])))
        elif k == 'num':
            toks.append(('num', int(v, 16) if v.lower().startswith('0x') else (float(v) if ('.' in v or 'e' in v.lower()) else int(v))))
        elif k == 'name':
            toks.append(('kw' if v in ('nil', 'true', 'false', 'function', 'end', 'return', 'local') else 'name', v))
        else:
            toks.append(('op', v))
    return toks


class Parser:
    def __init__(self, toks, env=None):
        self.t = toks
        self.i = 0
        self.env = env or {}

    def peek(self, o=0):
        j = self.i + o
        return self.t[j] if j < len(self.t) else ('eof', None)

    def next(self):
        tok = self.peek()
        self.i += 1
        return tok

    def expect(self, v):
        tok = self.next()
        if tok[1] != v:
            raise SyntaxError('expected %r got %r at token %d' % (v, tok, self.i))

    # expression with + - * / precedence
    def expr(self):
        left = self.term()
        while self.peek() in (('op', '+'), ('op', '-'), ('op', '..')):
            op = self.next()[1]
            right = self.term()
            left = self.binop(op, left, right)
        return left

    def term(self):
        left = self.unary()
        while self.peek() in (('op', '*'), ('op', '/'), ('op', '%')):
            op = self.next()[1]
            right = self.unary()
            left = self.binop(op, left, right)
        return left

    @staticmethod
    def binop(op, a, b):
        try:
            if op == '+': return a + b
            if op == '-': return a - b
            if op == '*': return a * b
            if op == '/': return a / b
            if op == '%': return a % b
            if op == '..': return str(a) + str(b)
        except TypeError:
            return None

    def unary(self):
        if self.peek() == ('op', '-'):
            self.next()
            v = self.unary()
            return -v if isinstance(v, (int, float)) else None
        if self.peek() == ('op', '#'):
            self.next()
            v = self.unary()
            return len(v) if v is not None else None
        return self.primary()

    def primary(self):
        tok = self.next()
        kind, v = tok
        if kind == 'num' or kind == 'str':
            val = v
        elif kind == 'kw' and v == 'nil':
            val = None
        elif kind == 'kw' and v in ('true', 'false'):
            val = (v == 'true')
        elif tok == ('op', '{'):
            val = self.table()
        elif tok == ('op', '('):
            val = self.expr()
            self.expect(')')
        elif kind == 'name':
            val = self.env.get(v)
            # suffixes: .name  [expr]  (args)  :method(args)
            while True:
                p = self.peek()
                if p == ('op', '.'):
                    self.next()
                    key = self.next()[1]
                    val = val.get(key) if isinstance(val, dict) else None
                elif p == ('op', '['):
                    self.next()
                    key = self.expr()
                    self.expect(']')
                    val = val.get(key) if isinstance(val, dict) else None
                elif p == ('op', '(') or p[0] == 'str' or p == ('op', '{'):
                    args = self.call_args()
                    val = args[0] if (v == 'l10n' and args) else None
                elif p == ('op', ':'):
                    self.next(); self.next()
                    self.call_args()
                    val = None
                else:
                    break
        else:
            raise SyntaxError('unexpected %r at token %d' % (tok, self.i))
        return val

    def call_args(self):
        p = self.peek()
        if p[0] == 'str':
            self.next()
            return [p[1]]
        if p == ('op', '{'):
            self.next()
            return [self.table()]
        self.expect('(')
        args = []
        if self.peek() != ('op', ')'):
            args.append(self.expr())
            while self.peek() == ('op', ','):
                self.next()
                args.append(self.expr())
        self.expect(')')
        return args

    def table(self):
        # opening brace already consumed; returns dict (positional keys are 1..n ints)
        out = {}
        pos = 1
        while True:
            p = self.peek()
            if p == ('op', '}'):
                self.next()
                return out
            if p == ('op', '['):
                self.next()
                key = self.expr()
                self.expect(']')
                self.expect('=')
                val = self.expr()
                if key is not None and not isinstance(key, (dict, list)):
                    out[key] = val
            elif p[0] == 'name' and self.peek(1) == ('op', '='):
                key = self.next()[1]
                self.next()
                out[key] = self.expr()
            else:
                val = self.expr()
                if val is not None:
                    out[pos] = val
                pos += 1
            if self.peek() in (('op', ','), ('op', ';')):
                self.next()


def parse_table_after(src, marker_regex, env=None, start=0):
    """Find marker (regex ending right before a '{'), parse the following table."""
    m = re.compile(marker_regex).search(src, start)
    if not m:
        return None
    rest = src[m.end():]
    brace = rest.index('{')
    toks = tokenize(rest[brace:])
    p = Parser(toks, env)
    p.next()  # '{'
    return p.table()


def as_list(t):
    if not isinstance(t, dict):
        return []
    return [t[i] for i in sorted(k for k in t if isinstance(k, int)) if t[i] is not None]
