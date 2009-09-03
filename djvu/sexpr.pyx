# Copyright ©  2007, 2008, 2009 Jakub Wilk <ubanus@users.sf.net>
#
# This package is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 dated June, 1991.
#
# This package is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.

'''
DjVuLibre bindings: module for handling Lisp S-expressions
'''

include 'common.pxi'

cdef extern from 'libdjvu/miniexp.h':
    int cexpr_is_int 'miniexp_numberp'(cexpr_t sexp) nogil
    int cexpr_to_int 'miniexp_to_int'(cexpr_t sexp) nogil
    cexpr_t int_to_cexpr 'miniexp_number'(int n) nogil
    
    int cexpr_is_symbol 'miniexp_symbolp'(cexpr_t sexp) nogil
    char* cexpr_to_symbol 'miniexp_to_name'(cexpr_t sexp) nogil
    cexpr_t symbol_to_cexpr 'miniexp_symbol'(char* name) nogil

    cexpr_t cexpr_nil 'miniexp_nil'
    cexpr_t cexpr_dummy 'miniexp_dummy'
    int cexpr_is_list 'miniexp_listp'(cexpr_t exp) nogil
    int cexpr_is_nonempty_list 'miniexp_consp'(cexpr_t exp) nogil
    int cexpr_length 'miniexp_length'(cexpr_t exp) nogil
    cexpr_t cexpr_head 'miniexp_car'(cexpr_t exp) nogil
    cexpr_t cexpr_tail 'miniexp_cdr'(cexpr_t exp) nogil
    cexpr_t cexpr_nth 'miniexp_nth'(int n, cexpr_t exp) nogil
    cexpr_t pair_to_cexpr 'miniexp_cons'(cexpr_t head, cexpr_t tail) nogil
    cexpr_t cexpr_replace_head 'miniexp_rplaca'(cexpr_t exp, cexpr_t new_head) nogil
    cexpr_t cexpr_replace_tail 'miniexp_rplacd'(cexpr_t exp, cexpr_t new_tail) nogil
    cexpr_t cexpr_reverse_list 'miniexp_reverse'(cexpr_t exp) nogil

    int cexpr_is_str 'miniexp_stringp'(cexpr_t cexpr) nogil
    char* cexpr_to_str 'miniexp_to_str'(cexpr_t cexpr) nogil
    cexpr_t str_to_cexpr 'miniexp_string'(char* s) nogil
    cexpr_t cexpr_substr 'miniexp_substring'(char* s, int n) nogil
    cexpr_t cexpr_concat 'miniexp_concat'(cexpr_t cexpr_list) nogil

    cexpr_t gc_lock 'minilisp_acquire_gc_lock'(cexpr_t cexpr) nogil
    cexpr_t gc_unlock 'minilisp_release_gc_lock'(cexpr_t cexpr) nogil
    
    cvar_t* cvar_new 'minivar_alloc'() nogil
    void cvar_free 'minivar_free'(cvar_t* v) nogil
    cexpr_t* cvar_ptr 'minivar_pointer'(cvar_t* v) nogil

    int (*io_puts 'minilisp_puts')(char *s)
    int (*io_getc 'minilisp_getc')()
    int (*io_ungetc 'minilisp_ungetc')(int c)
    cexpr_t cexpr_read 'miniexp_read'()
    cexpr_t cexpr_print 'miniexp_prin'(cexpr_t cexpr)
    cexpr_t cexpr_printw 'miniexp_pprin'(cexpr_t cexpr, int width)

cdef extern from 'stdio.h':
    int EOF

cdef object sys
import sys

cdef object StringIO
from cStringIO import StringIO

cdef object weakref
import weakref

cdef object symbol_dict
symbol_dict = weakref.WeakValueDictionary()

cdef Lock _myio_lock
_myio_lock = allocate_lock()
cdef object _myio_stdin
cdef object _myio_stdout
cdef int _myio_buffer
_myio_buffer = -1

cdef void myio_set(stdin, stdout):
    global _myio_stdin, _myio_stdout
    with nogil: acquire_lock(_myio_lock, WAIT_LOCK)
    _myio_stdin = stdin
    _myio_stdout = stdout

cdef void myio_reset():
    global _myio_stdin, _myio_stdout
    _myio_stdin = sys.stdin
    _myio_stdout = sys.stdout
    _myio_buffer = -1
    release_lock(_myio_lock)

cdef int _myio_puts(char *s):
    _myio_stdout.write(s)

cdef int _myio_getc():
    global _myio_buffer
    cdef int result
    result = _myio_buffer
    if result >= 0:
        _myio_buffer = -1
    else:
        s = _myio_stdin.read(1)
        if s:
            result = ord(s)
        else:
            result = EOF
    return result

cdef int _myio_ungetc(int c):
    global _myio_buffer
    if _myio_buffer >= 0:
        raise SystemError('ungetc() before getc()')
    _myio_buffer = c

io_puts = _myio_puts
io_getc = _myio_getc
io_ungetc = _myio_ungetc

cdef object the_sentinel
the_sentinel = object()

cdef class _WrappedCExpr:

    def __cinit__(self, object sentinel):
        if sentinel is not the_sentinel:
            raise_instantiation_error(type(self))
        self.cvar = cvar_new()

    cdef cexpr_t cexpr(self):
        return cvar_ptr(self.cvar)[0]

    cdef object print_into(self, object stdout, object width):
        cdef cexpr_t cexpr
        if width is None:
            pass
        elif not is_int(width):
            raise TypeError('width must be an integer')
        elif width <= 0:
            raise ValueError('width <= 0')
        cexpr = self.cexpr()
        myio_set(None, stdout)
        try:
            if width is None:
                cexpr_print(cexpr)
            else:
                cexpr_printw(cexpr, width)
        finally:
            myio_reset()

    cdef object as_string(self, object width):
        stdout = StringIO()
        try:
            self.print_into(stdout, width)
            return stdout.getvalue()
        finally:
            stdout.close()

    def __dealloc__(self):
        cvar_free(self.cvar)

cdef _WrappedCExpr wexpr(cexpr_t cexpr):
    cdef _WrappedCExpr wexpr
    wexpr = _WrappedCExpr(sentinel = the_sentinel)
    cvar_ptr(wexpr.cvar)[0] = cexpr
    return wexpr

cdef class _MissingCExpr(_WrappedCExpr):

    cdef object print_into(self, object stdout, object width):
        raise NotImplementedError
    
    cdef object as_string(self, object width):
        raise NotImplementedError

cdef _MissingCExpr wexpr_missing():
    return _MissingCExpr(the_sentinel)


cdef class BaseSymbol:

    cdef object __weakref__
    cdef object value

    def __cinit__(self, value):
        value = str(value)
        self.value = value

    def __repr__(self):
        return '%s(%r)' % (get_type_name(_Symbol_), self.value)
    
    def __richcmp__(self, object other, int op):
        cdef BaseSymbol _self, _other
        if not typecheck(self, BaseSymbol) or not typecheck(other, BaseSymbol):
            return NotImplemented
        _self = self
        _other = other
        if op == 2 or op == 3:
            return richcmp(_self.value, _other.value, op)
        return NotImplemented
    
    def __hash__(self):
        return hash(self.value)
    
    def __str__(self):
        return self.value
    
def Symbol__new__(cls, name):
    '''
    Symbol(name) -> a symbol
    '''
    self = None
    try:
        if cls is _Symbol_:
            self = symbol_dict[name]
    except KeyError:
        pass
    if self is None:
        name = str(name)
        self = BaseSymbol.__new__(cls, name)
        if cls is _Symbol_:
            symbol_dict[name] = self
    return self

class Symbol(BaseSymbol):
    __new__ = staticmethod(Symbol__new__)

cdef object _Symbol_
_Symbol_ = Symbol

del Symbol__new__

def Expression__new__(cls, value):
    '''
    Expression(value) -> an expression
    '''
    if typecheck(value, _Expression_) and (not typecheck(value, ListExpression) or not value):
        return value
    if is_int(value):
        return IntExpression(value)
    elif typecheck(value, _Symbol_):
        return SymbolExpression(value)
    elif is_unicode(value):
        return StringExpression(encode_utf8(value))
    elif is_string(value):
        return StringExpression(str(value))
    else:
        return ListExpression(iter(value))

def Expression_from_stream(stdin):
    '''
    Expression.from_stream(stream) -> an expression

    Read an expression from a stream.
    '''
    try:
        myio_set(stdin, None)
        try:
            return _c2py(cexpr_read())
        except InvalidExpression:
            raise ExpressionSyntaxError
    finally:
        myio_reset()

def Expression_from_string(str):
    '''
    Expression.from_string(s) -> an expression

    Read an expression from a string.
    '''
    stdin = StringIO(str)
    try:
        return _Expression_.from_stream(stdin)
    finally:
        stdin.close()

class Expression(BaseExpression):

    '''
    Notes about the textual representation of S-expressions
    -------------------------------------------------------

    Special characters are:

    * the parenthesis '(' and ')',
    * the double quote '"',
    * the vertical bar '|'.
    
    Symbols are represented by their name. Vertical bars | can be used to
    delimit names that contain blanks, special characters, non printable
    characters, non-ASCII characters, or can be confused as a number.
    
    Numbers follow the syntax specified by the C function strtol() with
    base=0.
    
    Strings are delimited by double quotes. All C string escapes are
    recognized. Non-printable ASCII characters must be escaped.
    
    List are represented by an open parenthesis '(' followed by the space
    separated list elements, followed by a closing parenthesis ')'.
    
    When the cdr of the last pair is non zero, the closed parenthesis is
    preceded by a space, a dot '.', a space, and the textual representation
    of the cdr. (This is only partially supported by Python bindings.)

    '''
    __new__ = staticmethod(Expression__new__)
    from_string = staticmethod(Expression_from_string)
    from_stream = staticmethod(Expression_from_stream)

cdef object _Expression_
_Expression_ = Expression

del Expression__new__, Expression_from_string, Expression_from_stream

cdef object BaseExpression_richcmp(object left, object right, int op):
    if not typecheck(left, BaseExpression):
        return NotImplemented
    elif not typecheck(right, BaseExpression):
        return NotImplemented
    return richcmp(left.value, right.value, op)

cdef class BaseExpression:
    '''
    Don't use this class directly. Use the Expression class instead.
    '''

    cdef _WrappedCExpr wexpr

    def __cinit__(self, *args, **kwargs):
        self.wexpr = wexpr_missing()

    def print_into(self, stdout, width = None):
        '''
        expr.print_into(file[, width]) -> None
        
        Print the expression into the file.
        '''
        self.wexpr.print_into(stdout, width)

    def as_string(self, width = None):
        '''
        expr.as_string([width]) -> a string

        Return a string representation of the expression.
        '''
        return self.wexpr.as_string(width)
    
    def __str__(self):
        return self.as_string()

    property value:
        '''
        The actual "pythonic" value of the expression.
        ''' 
        def __get__(self):
            return self._get_value()
    
    def _get_value(self):
        raise NotImplementedError

    def __richcmp__(self, other, int op):
        return BaseExpression_richcmp(self, other, op)

    def __repr__(self):
        return '%s(%r)' % (get_type_name(_Expression_), self.value)

    def __copy__(self):
        # Most of S-expressions are immutable.
        # Mutable S-expressions should override this method.
        return self
    
    def __deepcopy__(self, memo):
        # Most of S-expressions are immutable.
        # Mutable S-expressions should override this method.
        return self

def IntExpression__new__(cls, value):
    '''
    IntExpression(n) -> an integer expression
    '''
    cdef BaseExpression self
    self = BaseExpression.__new__(cls)
    if typecheck(value, _WrappedCExpr):
        self.wexpr = value
    elif is_int(value):
        if -1 << 29 <= value < 1 << 29:
            self.wexpr = wexpr(int_to_cexpr(value))
        else:
            raise ValueError('value not in range(-2 ** 29, 2 ** 29)')
    else:
        raise TypeError('value must be an integer')
    return self

class IntExpression(_Expression_):

    '''
    IntExpression can represent any integer in range(-2 ** 29, 2 ** 29).

    To create objects of this class, use the Expression class constructor.
    '''

    __new__ = staticmethod(IntExpression__new__)
    
    def __nonzero__(self):
        return bool(self.value)

    def __int__(self):
        return self.value

    def __long__(self):
        return 0L + self.value

    def _get_value(BaseExpression self not None):
        return cexpr_to_int(self.wexpr.cexpr())

    def __richcmp__(self, other, int op):
        return BaseExpression_richcmp(self, other, op)

    def __hash__(self):
        return hash(self.value)

del IntExpression__new__

def SymbolExpression__new__(cls, value):
    '''
    SymbolExpression(Symbol(s)) -> a symbol expression
    '''
    cdef BaseExpression self
    cdef BaseSymbol symbol
    self = BaseExpression.__new__(cls)
    if typecheck(value, _WrappedCExpr):
        self.wexpr = value
    elif typecheck(value, _Symbol_):
        symbol = value
        self.wexpr = wexpr(symbol_to_cexpr(symbol.value))
    else:
        raise TypeError('value must be a Symbol')
    return self

class SymbolExpression(_Expression_):
    '''
    To create objects of this class, use the Expression class constructor.
    '''

    __new__ = staticmethod(SymbolExpression__new__)

    def _get_value(BaseExpression self not None):
        return _Symbol_(cexpr_to_symbol(self.wexpr.cexpr()))

    def __richcmp__(self, other, int op):
        return BaseExpression_richcmp(self, other, op)

    def __hash__(self):
        return hash(self.value)

del SymbolExpression__new__

def StringExpression__new__(cls, value):
    '''
    SymbolExpression(s) -> a string expression
    '''
    cdef BaseExpression self
    self = BaseExpression.__new__(cls)
    if typecheck(value, _WrappedCExpr):
        self.wexpr = value
    elif is_string(value):
        gc_lock(NULL) # protect from collecting a just-created object
        try:
            self.wexpr = wexpr(str_to_cexpr(value))
        finally:
            gc_unlock(NULL)
    else:
        raise TypeError('value must be a byte string')
    return self

class StringExpression(_Expression_):
    '''
    To create objects of this class, use the Expression class constructor.
    '''
    __new__ = staticmethod(StringExpression__new__)

    def _get_value(BaseExpression self not None):
        return cexpr_to_str(self.wexpr.cexpr())

    def __richcmp__(self, other, int op):
        return BaseExpression_richcmp(self, other, op)

    def __hash__(self):
        return hash(self.value)

del StringExpression__new__

class InvalidExpression(ValueError):
    pass

class ExpressionSyntaxError(Exception):
    '''
    Invalid expression syntax.
    '''
    pass

cdef _WrappedCExpr public_py2c(object o):
    cdef BaseExpression pyexpr
    pyexpr = _Expression_(o)
    if pyexpr is None:
        raise TypeError
    return pyexpr.wexpr

cdef object public_c2py(cexpr_t cexpr):
    return _c2py(cexpr)

cdef BaseExpression _c2py(cexpr_t cexpr):
    if cexpr == cexpr_dummy:
        raise InvalidExpression
    _wexpr = wexpr(cexpr)
    if cexpr_is_int(cexpr):
        result = IntExpression(_wexpr)
    elif cexpr_is_symbol(cexpr):
        result = SymbolExpression(_wexpr)
    elif cexpr_is_list(cexpr):
        result = ListExpression(_wexpr)
    elif cexpr_is_str(cexpr):
        result = StringExpression(_wexpr)
    else:
        raise ValueError
    return result

cdef _WrappedCExpr _build_list_cexpr(object items):
    cdef cexpr_t cexpr
    cdef BaseExpression citem
    gc_lock(NULL) # protect from collecting a just-created object
    try:
        cexpr = cexpr_nil
        for item in items:
            if typecheck(item, BaseExpression):
                citem = item
            else:
                citem = _Expression_(item)
            if citem is None:
                raise TypeError
            cexpr = pair_to_cexpr(citem.wexpr.cexpr(), cexpr)
        cexpr = cexpr_reverse_list(cexpr)
        return wexpr(cexpr)
    finally:
        gc_unlock(NULL)

def ListExpression__new__(cls, items):
    '''
    ListExpression(iterable) -> a list expression
    '''
    cdef BaseExpression self
    self = BaseExpression.__new__(cls)
    if typecheck(items, _WrappedCExpr):
        self.wexpr = items
    else:
        self.wexpr = _build_list_cexpr(items)
    return self

class ListExpression(_Expression_):
    '''
    To create objects of this class, use the Expression class constructor.
    '''
    __new__ = staticmethod(ListExpression__new__)

    def __nonzero__(BaseExpression self not None):
        return self.wexpr.cexpr() != cexpr_nil

    def __len__(BaseExpression self not None):
        cdef cexpr_t cexpr
        cdef int n
        cexpr = self.wexpr.cexpr()
        n = 0
        while cexpr != cexpr_nil:
            cexpr = cexpr_tail(cexpr)
            n = n + 1
        return n

    def __getitem__(BaseExpression self not None, key):
        cdef cexpr_t cexpr
        cdef int n
        cexpr = self.wexpr.cexpr()
        if is_int(key):
            n = key
            if n < 0:
                n = n + len(self)
            if n < 0:
                raise IndexError('list index of out range')
            while 1:
                if cexpr == cexpr_nil:
                    raise IndexError('list index of out range')
                if n > 0:
                    n = n - 1
                    cexpr = cexpr_tail(cexpr)
                else:
                    cexpr = cexpr_head(cexpr)
                    break
        elif is_slice(key):
            if (is_int(key.start) or key.start is None) and key.stop is None and key.step is None:
                n = key.start or 0
                if n < 0:
                    n = n + len(self)
                while n > 0 and cexpr != cexpr_nil:
                    cexpr = cexpr_tail(cexpr)
                    n = n - 1
            else:
                raise NotImplementedError('only [n:] slices are supported')
        else:
            raise TypeError('key must be an integer or a slice')
        return _c2py(cexpr)

    def __setitem__(BaseExpression self not None, key, value):
        cdef cexpr_t cexpr
        cdef cexpr_t prev_cexpr
        cdef cexpr_t new_cexpr
        cdef int n
        cdef BaseExpression pyexpr
        cexpr = self.wexpr.cexpr()
        pyexpr = _Expression_(value)
        new_cexpr = pyexpr.wexpr.cexpr()
        if is_int(key):
            n = key
            if n < 0:
                n = n + len(self)
            if n < 0:
                raise IndexError('list index of out range')
            while 1:
                if cexpr == cexpr_nil:
                    raise IndexError('list index of out range')
                if n > 0:
                    n = n - 1
                    cexpr = cexpr_tail(cexpr)
                else:
                    cexpr_replace_head(cexpr, new_cexpr)
                    break
        elif is_slice(key):
            if not cexpr_is_list(new_cexpr):
                raise TypeError('can only assign a list expression')
            if (is_int(key.start) or key.start is None) and key.stop is None and key.step is None:
                n = key.start or 0
                if n < 0:
                    n = n + len(self)
                prev_cexpr = cexpr_nil
                while n > 0 and cexpr != cexpr_nil:
                    prev_cexpr = cexpr
                    cexpr = cexpr_tail(cexpr)
                    n = n - 1
                if prev_cexpr == cexpr_nil:
                    self.wexpr = wexpr(new_cexpr)
                else:
                    cexpr_replace_tail(prev_cexpr, new_cexpr)
            else:
                raise NotImplementedError('only [n:] slices are supported')
        else:
            raise TypeError('key must be an integer or a slice')

    def __iter__(self):
        return _ListExpressionIterator(self)
    
    def __hash__(self):
        raise TypeError('unhashable type: \'%s\'' % (get_type_name(type(self)),))

    def _get_value(BaseExpression self not None):
        cdef cexpr_t current
        current = self.wexpr.cexpr()
        result = []
        while current != cexpr_nil:
            list_append(result, _c2py(cexpr_head(current))._get_value())
            current = cexpr_tail(current)
        return tuple(result)
    
    def __copy__(self):
        return _Expression_(self)
    
    def __deepcopy__(self, memo):
        return _Expression_(self._get_value())

del ListExpression__new__

cdef class _ListExpressionIterator:

    cdef BaseExpression expression
    cdef cexpr_t cexpr

    def __cinit__(self, BaseExpression expression not None):
        self.expression = expression
        self.cexpr = expression.wexpr.cexpr()
    
    def __next__(self):
        cdef cexpr_t cexpr
        cexpr = self.cexpr
        if cexpr == cexpr_nil:
            raise StopIteration
        self.cexpr = cexpr_tail(cexpr)
        cexpr = cexpr_head(cexpr)
        return _c2py(cexpr)
    
    def __iter__(self):
        return self


__all__ = ('Symbol', 'Expression', 'IntExpression', 'SymbolExpression', 'StringExpression', 'ListExpression', 'InvalidExpression', 'ExpressionSyntaxError')
__author__ = 'Jakub Wilk <ubanus@users.sf.net>'
__version__ = PYTHON_DJVULIBRE_VERSION

# vim:ts=4 sw=4 et ft=pyrex