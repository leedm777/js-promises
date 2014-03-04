These specs demonstrate the basic features of a [Promises/A+][]
compliant implementation of JavaScript promises, and then digs into
some of the extras found in [Q][].

The code itself is written as [mocha][] specs, with [chai][] expectations.

    chai = require 'chai'
    expect = chai.expect

I'll use the [mocha-as-promised][] extension, which is helpful for
writing promise-based [mocha][] tests. Instead of fooling around with
the `done` callback, you simply have to return a promise with the
test's results.

    (require 'mocha-as-promised')()

# What is a promise?

    describe 'Promises', ->

From the Promises/A+ specification, ["A promise represents the eventual
result of an asynchronous operation."][defn] This gives a simpler way
to think about asynchronous execution, without the complexities of
either multi-threaded code or callback.

## Promise States

A promise is in one of three states.

 1. Pending (it has no value)
 2. Fulfilled (it has a value)
 3. Rejected (it has a reason, which is usually an exception)

When a promise is pending, it can transition to either fulfilled or
rejected. Once fulfilled or rejected, the promise is immutable. This
immutability is shallow. So while a promise cannot change its value,
the internals of the value itself may change.

But that would be shared mutable state, so it's not recommended.

# The `then` method

The Promises/A+ specification is actually very simple. It doesn't even
provide a standard mechanism for creating, fulfilling or rejecting
promises. It merely defines an interoperable `then` method.

A promise's `then` method takes two parameters: `onFulfilled` and
`onRejected`, both of which are optional. `then` always returns a
promise, which is fulfilled or rejected based on what the callbacks
do.

## onFulfilled

The `onFulfilled` handler is called, only once, after the promise is
fulfilled. The value of the promise is passed as the first argument.

      it 'should deliver a value to .then', ->
        later 42
          .then (actual) -> (expect actual).to.equal 42

## onRejected

The `onRejected` handler is called, only once, after the promise is
rejected. The reason of the promise is passed as the first argument.

      it 'should deliver a reason to .then', ->
        throwLater new Error 'Some Error'
          .then(
            (actual) -> assert.fail 'should not happen',
            (err) -> (expect err.message).to.equal 'Some Error')

## Asynchronous

The handlers are not called at least until the next tick. This means
that the callback will always be called asynchronously. This is
helpful if you have shared mutable state, but you shouldn't do that,
anyways.

      it 'should callback asynchronously', ->
        x = 'sync'
        p = later 42
          .then -> (expect x).to.equal 'async'
        x = 'async'
        p

## Maps values

If either handler returns a value, `then` returns a promise that
fulfills as that value.

      it 'should map callback results', ->
        later 42
          .then (x) -> x + 1
          .then (actual) -> (expect actual).to.equal 43

## Maps errors

If either handler throws an exception, `then` returns a rejected
promise with that exception as the reason.

      it 'should map callback exceptions', ->
        later 42
          .then -> throw new Error 'Some Error'
          .then(
            -> assert.fail 'should not happen',
            (err) -> (expect err.message).to.equal 'Some Error')

## Automagic flatmapping

If the callback returns an object with a `then` method (called a
'thenable' in the spec), then the promise attempts to assume the value
of the returned promise. The spec is a bit complicated, but it allows
different promise implementations to interoperate, and even allows for
the assimilation of some non-conformant `then` methods.

      it 'should flatmap promises', ->
        later 42
          .then (x) -> later x + 1
          .then (actual) -> (expect actual).to.equal 43

      it 'should be interoperable', ->
        Bluebird = require 'bluebird'
        bluebirdLater = (v) -> new Bluebird (resolve) -> resolve v

        later 42
          .then (x) -> bluebirdLater x + 1
          .then (actual) -> (expect actual).to.equal 43

# Q extensions

    Q = require 'q'

    describe 'Q extensions', ->

The `then` method, as defined in the Promises/A+ spec, is simple,
flexible and sufficient. But there are several situations where you'll
find yourself wanting more.

[Q][] is one of the more popular Promise libraries for JavaScript. It
works in the browser, and on Node.js. It is [Promises/A+][] compliant,
and has several extentions making it more usable.

## Convenience methods for `catch` and `finally`

Promise code can be written much like regular imperative code, without
the messy callback chains. Q promises offer `catch` and `finally`
methods duplicating this functionality in a promise-like manner.

There are corresponding `fail` and `fin` aliases which can be used in
non-ES5 environments.

      it 'should catch exceptions', ->
        throwLater new Error 'Some Error'
          .then -> assert.fail 'should not happen'
          .catch (err) -> (expect err.message).to.equal 'Some Error'

      it 'should fail if finally fails', ->
        later 42
          .finally -> throwLater new Error 'Finally Error'
          .catch (err) -> (expect err.message).to.equal 'Finally Error'

### Q.all

      describe 'Q.all', ->

Often times you'll have multiple promises running in parallel, and you
want to wait for all of the promises to resolve before processing.
`Q.all` is a wonderfully simple way to handle this.

        it 'should resolve all values', ->
          Q.all [ (later 1), (later 2), (later 3) ]
            .then (actual) -> (expect actual).to.deep.equal [1, 2, 3]

If any promise is rejected, the `Q.all` is rejected

        it 'should reject if any are rejected', ->
          Q.all [ (later 1), (later 2), (throwLater new Error 'All Error')]
            .then (actual) -> assert.fail 'should not happen'
            .catch (err) -> (expect err.message).to.equal 'All Error'

`Q.all` silently passes non-promise values through, making it
convenient to pass values along through the `.then` chain.

        it 'should pass values along', ->
          later 42
            .then (x) -> Q.all [ x, later x + 1 ]
            .then (actual) -> (expect actual).to.deep.equal [42, 43]

### `Q.allSettled`

      describe 'Q.allSettled', ->

Since `Q.all` fails if any promise fails, it rejects as soon as it
can. If you need to tolerate errors and wait for all promises to
complete before proceeding, use `Q.allSettled`. The returned promise
fulfills with the settled values/reasons for all the input promises.

        it 'should resolve all values and reasons', ->
          Q.allSettled [ (later 42), (throwLater new Error 'All Error')]
            .then (actual) ->
              (expect actual[0].state).to.equal 'fulfilled'
              (expect actual[0].value).to.equal 42
              (expect actual[1].state).to.equal 'rejected'
              (expect actual[1].reason.message).to.equal 'All Error'

### `.spread`

      describe '.spread', ->

Passing along an array is nice, but often you'll want to just pass a
set of arguments to the `then` handler. That's where `spread` comes
in. It's a `then` handler that takes the array the promise settles on
and spreads it across the callbacks arguments.

        it 'should spread arguments', ->
          later [1, 2, 3]
            .spread (a, b, c) ->
              (expect a).to.equal 1
              (expect b).to.equal 2
              (expect c).to.equal 3

This is especially nice in combination with `Q.all`.

        it 'should spread well with Q.all', ->
          Q.all [ (later 1), (later 2), (later 3) ]
            .spread (a, b, c) ->
              (expect a).to.equal 1
              (expect b).to.equal 2
              (expect c).to.equal 3

Spread does an implicit `Q.all` on the input array, so when chaining
`then` handlers together it's unnecessary.

        it 'should automagically Q.all the value', ->
          later 42
            .then (x) -> [x, later x + 1]
            .spread (x, y) ->
              (expect x).to.equal 42
              (expect y).to.equal 43

# Integrating with callbacks

Most of the JavaScript code in the wild today uses callbacks instead
of promises. Fortunately, Q offers a few helpers to bridge this gap.

## `fcall`

      describe 'fcall', ->

The first is a promise that is fulfilled or rejected based on the
results of invoking a function.

        it 'should fulfill with a functions return value', ->
          Q.fcall -> 42
            .then (actual) -> (expect actual).to.equal 42

        it 'should reject with a functions exceptions', ->
          Q.fcall -> throw new Error 'Some Error'
            .then -> assert.fail 'should not happen'
            .catch (err) -> (expect err.message).to.equal 'Some Error'

In these cases, though, it's almost always easier to just use the
static `Q.fulfill` or `Q.reject` functions.

        it 'fulfill is easier', ->
          Q.fulfill 42
            .then (actual) -> (expect actual).to.equal 42

        it 'should reject with a functions exceptions', ->
          Q.reject new Error 'Some Error'
            .then -> assert.fail 'should not happen'
            .catch (err) -> (expect err.message).to.equal 'Some Error'


## Deferred

      describe 'deferred', ->

Usually, though, the function you want to turn into a promise is
asynchronous. The basic building block of building your own promises
is the deferred object.

        it 'should fulfill when resolved', ->
          uut = Q.defer()
          laterClassic 42, (err, x) -> uut.resolve x
          uut.promise
              .then (actual) -> (expect actual).to.equal 42

        it 'should fulfill when rejected', ->
          uut = Q.defer()
          throwLaterClassic (new Error 'Error'), ((err, x) -> uut.reject(err))
          uut.promise
            .then -> assert.fail 'should not happen'
            .catch (err) -> (expect err.message).to.equal 'Error'

## Node.js adapters

Node.js has introduced a distinct callback pattern, where the final
parameter to a function is the callback, which has the signature
`(err, val) ->`. `nfcall` can adapt functions that use this pattern to
make them return a promise. (Or `nfapply` if you have the arguments
stacked in an array).

      describe 'nfcall', ->
        it 'should adapt a node.js function', ->
          Q.nfcall laterClassic, 42
            .then (actual) -> (expect actual).to.equal 42

Or `denodify` can create a reusable wrapper for you.

      describe 'denodify', ->
        it 'should create a wrapper', ->
          uut = Q.denodeify laterClassic
          uut 42
            .then (actual) -> (expect actual).to.equal 42

There are even adapters for instance methods.

      describe 'method adapters', ->
        class ValueObject
          constructor: (@value) ->
          val: (cb) -> laterClassic @value, cb

You can use `ninvoke` to invoke an async instance method and return a
promise. (Or `npost` if you have the arguments stacked in an array).

        describe 'ninvoke', ->
          it 'should create a promise from a method invocation', ->
            obj = new ValueObject 42
            Q.ninvoke(obj, 'val')
              .then (actual) -> (expect actual).to.equal 42

Similar to denodify, `nbind` can create a reusable wrapper.

        describe 'nbind', ->
          it 'should create a wrapper function', ->
            obj = new ValueObject 42
            uut = Q.nbind(obj.val, obj)
            uut()
              .then (actual) -> (expect actual).to.equal 42

## Creating callback+promise methods

Since promises are somewhat new, you may want to offer a familiar
callback-based API in addition to your promise API. A simple option
for this is to accept the callback as an optional parameter. If a
callback is provided, then chain a `done` on the returned promise that
invokes the callback appropriately.

      describe 'old school', ->
        oldSchool = (v, cb) ->
          if (cb)
            # Invoke callback when done
            oldSchool(v)
              .done(
                ((res) -> cb null, res),
                (err) -> cb err)
            return
          # Promise based implementation
          if (v == 0)
            Q.reject new Error 'Zero not allowed'
          else
            Q.fulfill v

        it 'should invoke on success', (done) ->
          oldSchool 42, (err, res) ->
            (expect res).to.equal 42
            done()

        it 'should invoke on error', (done) ->
          oldSchool 0, (err, res) ->
            (expect err.message).to.equal 'Zero not allowed'
            done()

# Other useful methods

## Delays/timeouts

      describe 'timer functions', ->

The results of a promise can be delayed by the `delay` method. Or a
timeout on resolving can be specified by the `timeout` method.

        it 'should timeout', ->
          later 42
            .delay 999
            .timeout 100, 'Timeout'
            .then (actual) -> assert.fail 'should not happen'
            .catch (err) -> (expect err.message).to.equal 'Timeout'

        it 'should delay', ->
          later 42
            .delay 100
            .timeout 999
            .then (actual) -> (expect actual).to.equal 42

## Sugar methods

There are a handful of other methods with provide either a bit of
sugar, or address common patterns when dealing with promises.

      describe 'useful methods', ->
        it 'should get fields from the value', ->
          later { x: 42 }
            .get 'x'
            # same as .then (v) -> v['x']
            .then (actual) -> (expect actual).to.equal 42

        it 'should invoke functions on the value', ->
          later { inc: (x) -> x + 1 }
            .invoke('inc', 41)
            # same as .then (v) -> v['inc'] 41
            .then (actual) -> (expect actual).to.equal 42

        it 'should get the property names of the value', ->
          later { foo: 1, bar: 2 }
            .keys()
            # same as .then (v) -> Object.keys v
            .then (actual) -> (expect actual).to.deep.equal ['foo', 'bar']

        it 'should thenResolve', ->
          later 1
            .thenResolve 42
            # same as .then -> 42
            .then (actual) -> (expect actual).to.equal 42

        it 'should thenReject', ->
          later 1
            .thenReject new Error 'Some Error'
            # same as .then -> throw new Error 'Some Error'
            .then -> assert.fail 'should not happen'
            .catch (err) -> (expect err.message).to.equal 'Some Error'

# Other stuff to keep in mind

## Event listeners are not callbacks

It's a subtle point, but there's a difference between a 'callback' and
an 'event listener'.

A callback is a function for asyncrounously returning the value (or
exception) of an execution. Callbacks are called exactly once, with
either an error or some value.

An event listener is a function for asynchronously being notified of
events. These events may not happen at all, or may happen multiple
times.

Promises are suitable for callbacks, but not for event listeners.

## Return callbacks; don't accept deferred

When transitioning from callbacks to promises, sometimes it feels
natural to accept a deferred as a parameter to your functions. This is
an anti-pattern, and should be avoided.

This forces your caller to build the deferred before invoking your
function, and extract its promise before then can do anything with it.

    dontDoThis = (deferred, v) ->
      deferred.fulfill v

    becauseOfThis = ->
      d = Q.deferred() # This pattern is duplicated by all callers
      dontDoThis d, 42
      d.promise
        .then (v) ->

It's better to just build the deferred yourself. Often times, you can
do it more efficiently, anyways.

    doThisInstead = (v) ->
      Q.fulfill v

    becauseClientCodeIsNicer = ->
      doThisInstead 42
        .then (v) ->

## Either return or end your promises

One of the dangers with promises is that they look a lot like
asynchronous code, but don't have the synchronous behavior of bubbling
up exceptions. This unfortunately means that it's easy to silently
drop exceptions if they aren't handled.

If you are returning your promise, then you can assume that the caller
is handling errors (just like bubbling exceptions up the call stack).

    returningPromise = ->
      foo()
        .then -> 'bar'

But if you're not returning the promise, then you should end your
promise with `done`. If an unhandled error makes its way to `done`,
the error is rethrown and reported.

    internalPromise = ->
      foo()
        .then(->) # do something
        .done()

From the [Q docs][golden rule]:
> The Golden Rule of `done` vs. `then` usage is: either `return` your promise to someone else, or if the chain ends with you, call `done` to terminate it.

## Long stack support

A big problem with asynchronous code in general is that stack traces
become effectively useless.

Q's promises, though, offer a solution. Since promise invocations are
chained together, the stacks of each step in the chain can be tracked.
This makes tracking back through the chain of promises actually
possible.

To enable long stack support, set `Q.longStackSupport` to `true`.

# Generators

[Harmony Generators][] is a proposal for ES6 which, when combined with
promises, makes the use of promises from JavaScript entirely a magical
experience. These are similar to generators in Python, or the macro
rewrite magic that happens in Clojure's core.async.

These are still being worked on in JavaScript, and will probably come
to CoffeeScript [some time after that][generator-pr].

Generators provide a way to suspend function execution (at a `yield`),
which can be resumed at some later point.

The `Q.spawn` function can continue to execute a generator. Whenever
the generator yields a promise, Q waits for that promise to complete
and then continues on with execution.

    ### Commented out; required Node.js 0.11 or later with --harmony
    ` // And in JavaScript, since CoffeScript is still being hammered out
    describe('JavaScript generator', function () {
      it('should look like normal code', function () {
        Q.spawn(function *() {
          var actual = yield later 42;
          (expect actual).to.equal 42;
        });
      });

      it('even exceptions should look normal', function () {
        Q.spawn(function *() {
          try {
            yield throwLater new Error 'Some Error';
            assert.fail 'should not happen';
          } catch (err) {
            (expect err.message).to.equal 'Some Error';
          }
        });
      });
    });
    `
    ###

# Test utilities

In case you're curious about the functions I used the above specs.

    later = (value) -> Q.fulfill value
    throwLater = (err) -> Q.reject err

    laterClassic = (value, cb) -> process.nextTick -> (cb null, value)
    throwLaterClassic = (err, cb) -> process.nextTick -> (cb err)


 [Promises/A+]: http://promisesaplus.com/
 [Q]: http://documentup.com/kriskowal/q/
 [chai]: http://chaijs.com/api/bdd/
 [defn]: http://promisesaplus.com/#point-2
 [mocha-as-promised]: https://github.com/domenic/mocha-as-promised
 [mocha]: http://visionmedia.github.io/mocha/
 [golden rule]: https://github.com/kriskowal/q/wiki/API-Reference#wiki-promisedoneonfulfilled-onrejected-onprogress
 [Harmony Generators]: http://wiki.ecmascript.org/doku.php?id=harmony:generators
 [generator-pr]: https://github.com/jashkenas/coffee-script/pull/3078
