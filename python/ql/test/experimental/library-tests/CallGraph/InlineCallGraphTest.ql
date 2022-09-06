import python
import TestUtilities.InlineExpectationsTest
private import semmle.python.dataflow.new.internal.DataFlowDispatch as TT

/** Holds when `call` is resolved to `callable` using points-to based call-graph. */
predicate pointsToCallEdge(CallNode call, Function callable) {
  exists(call.getLocation().getFile().getRelativePath()) and
  exists(callable.getLocation().getFile().getRelativePath()) and
  // I did try using viableCallable from `DataFlowDispatchPointsTo` (from temporary copy
  //  of `dataflow.new.internal` that still uses points-to) instead of direct
  //  `getACall()` on a Value, but it only added results for `__init__` methods, not for
  //  anything else.
  exists(PythonFunctionValue funcValue |
    funcValue.getScope() = callable and
    call = funcValue.getACall()
  )
}

/** Holds when `call` is resolved to `callable` using type-tracking based call-graph. */
predicate typeTrackerCallEdge(CallNode call, Function callable) {
  exists(call.getLocation().getFile().getRelativePath()) and
  exists(callable.getLocation().getFile().getRelativePath()) and
  exists(TT::DataFlowCallable dfCallable, TT::DataFlowCall dfCall |
    dfCallable.getScope() = callable and
    dfCall.getNode() = call and
    dfCallable = TT::viableCallable(dfCall)
  )
}

/** Holds if the call edge is from a class call. */
predicate typeTrackerClassCall(CallNode call, Function callable) {
  exists(call.getLocation().getFile().getRelativePath()) and
  exists(callable.getLocation().getFile().getRelativePath()) and
  exists(TT::NormalCall cc |
    cc = TT::TNormalCall(call, _, any(TT::TCallType t | t instanceof TT::CallTypeClass)) and
    TT::TFunction(callable) = TT::viableCallable(cc)
  )
}

class CallGraphTest extends InlineExpectationsTest {
  CallGraphTest() { this = "CallGraphTest" }

  override string getARelevantTag() { result in ["pt", "tt"] }

  override predicate hasActualResult(Location location, string element, string tag, string value) {
    exists(location.getFile().getRelativePath()) and
    exists(CallNode call, Function target |
      tag = "tt" and
      typeTrackerCallEdge(call, target)
      or
      tag = "pt" and
      pointsToCallEdge(call, target)
    |
      location = call.getLocation() and
      element = call.toString() and
      if call.getLocation().getFile() = target.getLocation().getFile()
      then value = betterQualName(target)
      else
        exists(string fixedRelativePath |
          fixedRelativePath =
            target
                .getLocation()
                .getFile()
                .getRelativePath()
                .regexpCapture(".*/CallGraph[^/]*/(.*)", 1)
        |
          // the value needs to be enclosed in quotes to allow special characters
          value = "\"" + fixedRelativePath + ":" + betterQualName(target) + "\""
        )
    )
  }
}

bindingset[func]
string betterQualName(Function func) {
  // note: `target.getQualifiedName` for Lambdas is just "lambda", so is not very useful :|
  not func.isLambda() and
  result = func.getQualifiedName()
  or
  func.isLambda() and
  result =
    "lambda[" + func.getLocation().getFile().getShortName() + ":" +
      func.getLocation().getStartLine() + ":" + func.getLocation().getStartColumn() + "]"
}

query predicate debug_callableNotUnique(Function callable, string message) {
  exists(callable.getLocation().getFile().getRelativePath()) and
  exists(Function f |
    f != callable and
    f.getQualifiedName() = callable.getQualifiedName() and
    f.getLocation().getFile() = callable.getLocation().getFile()
  ) and
  message =
    "Qualified function name '" + callable.getQualifiedName() +
      "' is not unique within its file. Please fix."
}

query predicate pointsTo_found_typeTracker_notFound(CallNode call, string qualname) {
  exists(Function target |
    pointsToCallEdge(call, target) and
    not typeTrackerCallEdge(call, target) and
    qualname = betterQualName(target)
  )
}

query predicate typeTracker_found_pointsTo_notFound(CallNode call, string qualname) {
  exists(Function target |
    not pointsToCallEdge(call, target) and
    typeTrackerCallEdge(call, target) and
    qualname = betterQualName(target) and
    // We filter out result differences for points-to and type-tracking for class calls,
    // since otherwise it gives too much noise (these are just handled differently
    // between the two).
    not typeTrackerClassCall(call, target)
  )
}