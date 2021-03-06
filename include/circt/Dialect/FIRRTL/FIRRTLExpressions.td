//===- FIRRTLExpressions.td - FIRRTL expression ops --------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This describes the MLIR ops for FIRRTL expressions.
//
//===----------------------------------------------------------------------===//

def ConstantOp : FIRRTLOp<"constant", [NoSideEffect, ConstantLike,
                                       FirstAttrDerivedResultType]> {
  let summary = "Produce a constant value";
  let description = [{
    The constant operation produces a constant value of SInt or UInt type, it
    never produces a zero bit wide result.
    ```
      %result = firrtl.constant 42 : t1
    ```
    }];

  let arguments = (ins APIntAttr:$value);
  let results = (outs NonZeroIntType:$result);

  let assemblyFormat = "`(` $value `)` attr-dict `:` type($result)";

  let builders = [
    OpBuilderDAG<(ins "IntType":$type, "const APInt &":$value)>
  ];
  let hasFolder = 1;
  let verifier = "return ::verifyConstantOp(*this);";
}

def SubfieldOp : FIRRTLOp<"subfield", [NoSideEffect]> {
  let summary = "Extract a subfield of another value";
  let description = [{
    The subfield expression refers to a subelement of an expression with a
    bundle type.
    ```
      %result = firrtl.subfield %input "fieldname" : t1, t2
    ```
    }];

  let arguments = (ins FIRRTLType:$input, StrAttr:$fieldname);
  let results = (outs FIRRTLType:$result);

  // TODO: Could drop the result type, inferring it from the source.
  let assemblyFormat =
    "$input `(` $fieldname `)` attr-dict `:` functional-type($input, $result)";

  let extraClassDeclaration = [{
    /// Compute the result of a Subfield operation on a value of the specified
    /// type and extracting the specified field name.  If the request is
    /// invalid, then a null type is returned.
    static FIRRTLType getResultType(FIRRTLType inType, StringRef fieldName,
                                    Location loc);
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(input().getType().cast<FIRRTLType>(), fieldname());
  }];
}

class IndexConstraint<string value, string resultValue>
  : TypesMatchWith<"type should be element of array type",
                   value, resultValue,
                   "firrtl::getArrayElementType($_self)">;

def SubindexOp : FIRRTLOp<"subindex", [NoSideEffect, 
                                       IndexConstraint<"input", "result">]> {
  let summary = "Extract an element of a vector value";
  let description = [{
    The subindex expression statically refers, by index, to a subelement
    of an expression with a vector type. The index must be a non-negative
    integer and cannot be equal to or exceed the length of the vector it
    indexes.
    ```
      %result = firrtl.subindex %input[index] : t1
    ```
    }];

  let arguments = (ins FVectorType:$input, I32Attr:$index);
  let results = (outs FIRRTLType:$result);

  // TODO: Could drop the result type, inferring it from the source.
  let assemblyFormat =
     "$input `[` $index `]` attr-dict `:` type($input)";

  let extraClassDeclaration = [{
    /// Compute the result of a Subindex operation on a value of the specified
    /// type.  If the request is invalid, then a null type is returned.
    static FIRRTLType getResultType(FIRRTLType inType, unsigned fieldIdx,
                                    Location loc);
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(input().getType().cast<FIRRTLType>(), index());
  }];
}

def SubaccessOp : FIRRTLOp<"subaccess", [NoSideEffect, 
                                         IndexConstraint<"input", "result">]> {
  let summary = "Extract a dynamic element of a vector value";
  let description = [{
    The subaccess expression dynamically refers to a subelement of a
    vector-typed expression using a calculated index. The index must be an
    expression with an unsigned integer type.
    ```
      %result = firrtl.subaccess %input[%idx] : t1, t2
    ```
    }];

  let arguments = (ins FIRRTLType:$input, UIntType:$index);
  let results = (outs FIRRTLType:$result);

  // TODO: Could drop the result type, inferring it from the source.
  let assemblyFormat =
     "$input `[` $index `]` attr-dict `:` type($input) `,` type($index)";

  let extraClassDeclaration = [{
    /// Compute the result of a Subaccess operation on a value of the specified
    /// type.  If the request is invalid, then a null type is returned.
    static FIRRTLType getResultType(FIRRTLType baseType, FIRRTLType indexType,
                                    Location loc);
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(input().getType().cast<FIRRTLType>(),
                           index().getType().cast<FIRRTLType>());
  }];
}
//===----------------------------------------------------------------------===//
// Primitive Operations
//===----------------------------------------------------------------------===//

/// PrimOp is a FIRRTLOp without side effects.
class PrimOp<string mnemonic, list<OpTrait> traits = []> :
    FIRRTLOp<mnemonic, traits # [NoSideEffect]>;

//===----------------------------------------------------------------------===//
// Binary Operations
//===----------------------------------------------------------------------===//

// Base class for binary primitive operators.
class BinaryPrimOp<string mnemonic, Type lhsType, Type rhsType, Type resultType,
                   list<OpTrait> traits = []> :
    PrimOp<mnemonic, traits> {
  let arguments = (ins lhsType:$lhs, rhsType:$rhs);
  let results = (outs resultType:$result);

  let assemblyFormat = [{
    $lhs `,` $rhs  attr-dict `:`
       `(` type($lhs) `,` type($rhs) `)` `->` type($result)
  }];

  let extraClassDeclaration = [{
    /// Return the result for inputs with the specified type, returning a null
    /// type if the input types are invalid.
    static FIRRTLType getResultType(FIRRTLType lhs, FIRRTLType rhs, Location loc);
    static FIRRTLType getResultType(ArrayRef<FIRRTLType> inputs,
                                    ArrayRef<int32_t> integers, Location loc) {
      if (inputs.size() != 2 || !integers.empty()) {
        mlir::emitError(loc,"operation requires two operands and no constants");
        return {};
      }
      return getResultType(inputs[0], inputs[1], loc);
    }
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(lhs().getType().cast<FIRRTLType>(),
                           rhs().getType().cast<FIRRTLType>());
  }];
}

def AddPrimOp : BinaryPrimOp<"add", IntType, IntType, IntType, [Commutative]>;
def SubPrimOp : BinaryPrimOp<"sub", IntType, IntType, IntType>;
def MulPrimOp : BinaryPrimOp<"mul", IntType, IntType, IntType, [Commutative]>;
def DivPrimOp : BinaryPrimOp<"div", IntType, IntType, IntType> {
  let hasFolder = 1;
  let description = [{
    Divides the first argument (the numerator) by the second argument
    (the denominator) truncating the result (rounding towards zero).

    **If the denominator is zero, the result is undefined.**

    The compiler may optimize this undefined behavior in any way it
    wants. Notably `div(a, a)` will be optimized to `1`. This may cause
    erroneous formal equivalence mismatches between unoptimized and
    optimized FIRRTL dialects that are separately converted to Verilog.
  }];
}
def RemPrimOp : BinaryPrimOp<"rem", IntType, IntType, IntType>;

def AndPrimOp : BinaryPrimOp<"and", IntType, IntType, UIntType, [Commutative]> {
  let hasFolder = 1;
}
def OrPrimOp  : BinaryPrimOp<"or",  IntType, IntType, UIntType, [Commutative]> {
  let hasFolder = 1;
}
def XorPrimOp : BinaryPrimOp<"xor", IntType, IntType, UIntType, [Commutative]> {
  let hasFolder = 1;
}

// Comparison Operations
def LEQPrimOp : BinaryPrimOp<"leq", IntType, IntType, UInt1Type>;
def LTPrimOp  : BinaryPrimOp<"lt",  IntType, IntType, UInt1Type>;
def GEQPrimOp : BinaryPrimOp<"geq", IntType, IntType, UInt1Type>;
def GTPrimOp  : BinaryPrimOp<"gt",  IntType, IntType, UInt1Type>;
def EQPrimOp  : BinaryPrimOp<"eq",  IntType, IntType, UInt1Type, [Commutative]>{
  let hasFolder = 1;
}
def NEQPrimOp : BinaryPrimOp<"neq", IntType, IntType, UInt1Type, [Commutative]>{
  let hasFolder = 1;
}

def CatPrimOp   : BinaryPrimOp<"cat", IntType, IntType, UIntType> {
  let hasCanonicalizer = 1;
}
def DShlPrimOp  : BinaryPrimOp<"dshl", IntType, UIntType, IntType>;
def DShlwPrimOp : BinaryPrimOp<"dshlw", IntType, UIntType, IntType>;
def DShrPrimOp  : BinaryPrimOp<"dshr", IntType, UIntType, IntType>;

def ValidIfPrimOp
  : BinaryPrimOp<"validif", UInt1Type, PassiveType, PassiveType>;

//===----------------------------------------------------------------------===//
// Unary Operations
//===----------------------------------------------------------------------===//

// Base class for binary primitive operators.
class UnaryPrimOp<string mnemonic, Type srcType, Type resultType,
                  list<OpTrait> traits = []> :
    PrimOp<mnemonic, traits> {
  let arguments = (ins srcType:$input);
  let results = (outs resultType:$result);

  let assemblyFormat =
    "$input attr-dict `:` functional-type($input, $result)";

  let extraClassDeclaration = [{
    /// Return the result for inputs with the specified type, returning a null
    /// type if the input type is invalid.
    static FIRRTLType getResultType(FIRRTLType input, Location loc);
    static FIRRTLType getResultType(ArrayRef<FIRRTLType> inputs,
                                    ArrayRef<int32_t> integers, Location loc) {
      if (inputs.size() != 1 || !integers.empty()) {
        mlir::emitError(loc, "operation requires one operand and no constants");
        return {};
      }
      return getResultType(inputs[0], loc);
    }
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(input().getType().cast<FIRRTLType>());
  }];
}

def AsSIntPrimOp : UnaryPrimOp<"asSInt", FIRRTLType, SIntType> {
  let hasFolder = 1;
}
def AsUIntPrimOp : UnaryPrimOp<"asUInt", FIRRTLType, UIntType> {
  let hasFolder = 1;
}
def AsAsyncResetPrimOp
  : UnaryPrimOp<"asAsyncReset", OneBitCastableType, AsyncResetType>;
def AsClockPrimOp : UnaryPrimOp<"asClock", OneBitCastableType, ClockType>;
def CvtPrimOp : UnaryPrimOp<"cvt", IntType, SIntType>;
def NegPrimOp : UnaryPrimOp<"neg", IntType, SIntType>;
def NotPrimOp : UnaryPrimOp<"not", IntType, UIntType>;

def AndRPrimOp : UnaryPrimOp<"andr", IntType, UIntType> {
  let description = [{
    Horizontally reduce a value to one bit, using the 'and' operation to merge
    bits.  `andr(x)` is equivalent to `concat(x, 1b1) == ~0`.  As such, it
    returns 1 for zero-bit-wide operands.
  }];
}
def OrRPrimOp : UnaryPrimOp<"orr", IntType, UIntType> {
  let description = [{
    Horizontally reduce a value to one bit, using the 'or' operation to merge
    bits.  `orr(x)` is equivalent to `concat(x, 1b0) != 0`.  As such, it returns
    0 for zero-bit-wide operands.
  }];
}
def XorRPrimOp : UnaryPrimOp<"xorr", IntType, UIntType> {
  let description = [{
    Horizontally reduce a value to one bit, using the 'xor' operation to merge
    bits.  `xorr(x)` is equivalent to `popcount(concat(x, 1b0)) & 1`.  As such,
    it returns 0 for zero-bit-wide operands.
  }];
}

//===----------------------------------------------------------------------===//
// Other Operations
//===----------------------------------------------------------------------===//

def BitsPrimOp : PrimOp<"bits"> {
  let arguments = (ins IntType:$input, I32Attr:$hi, I32Attr:$lo);
  let results = (outs UIntType:$result);

  let assemblyFormat =
    "$input $hi `to` $lo attr-dict `:` functional-type($input, $result)";

  let description = [{
    The `bits` operation extracts the bits between `hi` (inclusive) and `lo`
    (inclusive) from `input`.  `hi` must be greater than or equal to `lo`. Both
    `hi` and `lo` must be non-negative and less than the bit width of `input`.
    The result is `hi - lo + 1` bits wide.
  }];

  let hasCanonicalizer = 1;
  let hasFolder = 1;

  let builders = [
    OpBuilderDAG<(ins "Value":$input, "unsigned":$high, "unsigned":$low)>
  ];

  let extraClassDeclaration = [{
    /// Return the result for inputs with the specified type, returning a null
    /// type if the input types are invalid.
    static FIRRTLType getResultType(FIRRTLType input, int32_t high,
                                    int32_t low, Location loc);
    static FIRRTLType getResultType(ArrayRef<FIRRTLType> inputs,
                                    ArrayRef<int32_t> integers, Location loc) {
      if (inputs.size() != 1 || integers.size() != 2) {
        mlir::emitError(loc,"operation requires one operand and two constants");
        return {};
      }
      return getResultType(inputs[0], integers[0], integers[1], loc);
    }
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(input().getType().cast<FIRRTLType>(), hi(), lo());
  }];
}

def HeadPrimOp : PrimOp<"head"> {
  let arguments = (ins IntType:$input, I32Attr:$amount);
  let results = (outs UIntType:$result);

  let assemblyFormat =
    "$input `,` $amount attr-dict `:` functional-type($input, $result)";

  let hasCanonicalizer = 1;

  let extraClassDeclaration = [{
    /// Return the result for inputs with the specified type, returning a null
    /// type if the input types are invalid.
    static FIRRTLType getResultType(FIRRTLType input, int32_t amount,
                                    Location loc);
    static FIRRTLType getResultType(ArrayRef<FIRRTLType> inputs,
                                    ArrayRef<int32_t> integers, Location loc) {
      if (inputs.size() != 1 || integers.size() != 1) {
        mlir::emitError(loc, "operation requires one operand and one constant");
        return {};
      }
      return getResultType(inputs[0], integers[0], loc);
    }
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(input().getType().cast<FIRRTLType>(), amount());
  }];
}

def InvalidValuePrimOp : PrimOp<"invalidvalue"> {
  let summary = "InvalidValue primitive";
  let description = [{
    The InvalidValue operation returns an invalid value of a specified type:
    ```
      %result = firrtl.invalid : !firrtl.uint<1>
    ```

    This corresponds to the FIRRTL invalidate operation without the implicit
    connect semantics.
  }];

  let arguments = (ins);
  let results = (outs FIRRTLType:$result);

  let assemblyFormat = "attr-dict `:` type($result)";
}

def MuxPrimOp : PrimOp<"mux"> {
  let arguments = (ins UInt1Type:$sel, PassiveType:$high, PassiveType:$low);
  let results = (outs PassiveType:$result);

  let assemblyFormat =
    "`(` operands `)` attr-dict `:` functional-type(operands, $result)";

  let hasFolder = 1;

  let extraClassDeclaration = [{
    /// Return the result for inputs with the specified type, returning a null
    /// type if the input types are invalid.
    static FIRRTLType getResultType(FIRRTLType sel, FIRRTLType high,
                                    FIRRTLType low, Location loc);
    static FIRRTLType getResultType(ArrayRef<FIRRTLType> inputs,
                                    ArrayRef<int32_t> integers, Location loc) {
      if (inputs.size() != 3 || !integers.empty()) {
        mlir::emitError(loc,
                        "operation requires three operands and no constants");
        return {};
      }

      return getResultType(inputs[0], inputs[1], inputs[2], loc);
    }
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(sel().getType().cast<FIRRTLType>(),
                           high().getType().cast<FIRRTLType>(),
                           low().getType().cast<FIRRTLType>());
  }];
}

def PadPrimOp : PrimOp<"pad"> {
  let arguments = (ins IntType:$input, I32Attr:$amount);
  let results = (outs IntType:$result);

  let assemblyFormat =
    "$input `,` $amount attr-dict `:` functional-type($input, $result)";

  let description = [{
    Pad the input out to an `amount` wide integer, sign extending or zero
    extending according to `input`s type.  If `amount` is less than the existing
    width of `input`, then input is unmodified.
  }];

  let hasFolder = 1;

  let extraClassDeclaration = [{
    /// Return the result for inputs with the specified type, returning a null
    /// type if the input types are invalid.
    static FIRRTLType getResultType(FIRRTLType input, int32_t amount,
                                    Location loc);
    static FIRRTLType getResultType(ArrayRef<FIRRTLType> inputs,
                                    ArrayRef<int32_t> integers, Location loc) {
      if (inputs.size() != 1 || integers.size() != 1) {
        mlir::emitError(loc, "operation requires one operand and one constant");
        return {};
      }

      return getResultType(inputs[0], integers[0], loc);
    }
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(input().getType().cast<FIRRTLType>(), amount());
  }];
}

class ShiftPrimOp<string mnemonic> : PrimOp<mnemonic> {
  let arguments = (ins IntType:$input, I32Attr:$amount);
  let results = (outs IntType:$result);

  let assemblyFormat =
    "$input `,` $amount attr-dict `:` functional-type($input, $result)";

  let extraClassDeclaration = [{
    /// Return the result for inputs with the specified type, returning a null
    /// type if the input types are invalid.
    static FIRRTLType getResultType(FIRRTLType input, int32_t amount,
                                    Location loc);
    static FIRRTLType getResultType(ArrayRef<FIRRTLType> inputs,
                                    ArrayRef<int32_t> integers, Location loc) {
      if (inputs.size() != 1 || integers.size() != 1) {
        mlir::emitError(loc, "operation requires one operand and one constant");
        return {};
      }
      return getResultType(inputs[0], integers[0], loc);
    }
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(input().getType().cast<FIRRTLType>(), amount());
  }];
}

def ShlPrimOp : ShiftPrimOp<"shl"> {
  let description = [{
    The `shl` operation concatenates `amount` zero bits to the least significant
    end of `input`. `amount` must be non-negative.
  }];

  let hasFolder = 1;
}

def ShrPrimOp : ShiftPrimOp<"shr"> {
  let description = [{
    The `shr` operation truncates least significant `amount` bits from `input`.
    If `amount` is greater than of equal to `width(input)`, the value will be
    zero for unsigned types and the sign bit for signed types. `amount` must be
    non-negative.
  }];

  let hasFolder = 1;
  let hasCanonicalizer = 1;
}

def TailPrimOp : PrimOp<"tail"> {
  let arguments = (ins IntType:$input, I32Attr:$amount);
  let results = (outs UIntType:$result);

  let assemblyFormat =
    "$input `,` $amount attr-dict `:` functional-type($input, $result)";

  let description = [{
    The `tail` operation truncates the `amount` most significant bits from
    `input`.  `amount` must be non-negative and less than or equal to the bit
    width of e. The result is `width(input)-amount` bits wide.
  }];

  let hasCanonicalizer = 1;

  let extraClassDeclaration = [{
    /// Return the result for inputs with the specified type, returning a null
    /// type if the input types are invalid.
    static FIRRTLType getResultType(FIRRTLType input, int32_t amount,
                                    Location loc);
    static FIRRTLType getResultType(ArrayRef<FIRRTLType> inputs,
                                    ArrayRef<int32_t> integers, Location loc) {
      if (inputs.size() != 1 || integers.size() != 1) {
        mlir::emitError(loc, "operation requires one operand and one constant");
        return {};
      }
      return getResultType(inputs[0], integers[0], loc);
    }
  }];

  let verifier = [{
    VERIFY_RESULT_TYPE_RET(input().getType().cast<FIRRTLType>(), amount());
  }];
}

//===----------------------------------------------------------------------===//
// Conversions to/from fixed-width signless integer types in standard dialect.
//===----------------------------------------------------------------------===//

// firrtl.stdIntCast takes inputs and results that are either signless integers
// or integer-like things in the FIRRTL dialect.
def IntCastType : AnyTypeOf<[PassiveType, AnySignlessInteger],
                            "passive FIRRTL type or signless builtin integer">;

// This operation converts from an SInt/UInt/Clock/etc to a signless integer
// type, or visa-versa.  FIRRTL source/destination types must be passive.
def StdIntCastOp : FIRRTLOp<"stdIntCast", [NoSideEffect]> {
  let arguments = (ins IntCastType:$input);
  let results = (outs IntCastType:$result);

  let assemblyFormat =
    "$input attr-dict `:` functional-type($input, $result)";

  let hasFolder = 1;
  let verifier = "return ::verifyStdIntCastOp(*this);";
}

// This operation converts from an Analog type to an InOut type of the
// corresponding width, or visa-versa.
def AnalogInOutCastOp : FIRRTLOp<"analogInOutCast", [NoSideEffect]> {
  let arguments = (ins AnyType:$input);
  let results = (outs AnyType:$result);

  let assemblyFormat =
    "$input attr-dict `:` functional-type($input, $result)";

  let hasFolder = 1;
  let verifier = "return ::verifyAnalogInOutCastOp(*this);";
}

// This operation converts from a struct to a bundle
// type, or visa-versa.  FIRRTL source/destination types must be passive.
def RTLStructCastOp : FIRRTLOp<"rtlStructCast", [NoSideEffect]> {
  let arguments = (ins AnyType:$input);
  let results = (outs AnyType:$result);

  let assemblyFormat =
    "$input attr-dict `:` functional-type($input, $result)";

  let verifier = "return ::verifyRTLStructCastOp(*this);";
}

// MLIR specific pseudo ops.


class PassiveConstraint<string value, string resultValue>
  : TypesMatchWith<"type should be a passive type",
                   value, resultValue,
                   "firrtl::getPassiveType($_self)">;

// Convert a value with non-passive type to a value with passive type.
def AsPassivePrimOp : FIRRTLOp<"asPassive", [NoSideEffect, 
                               PassiveConstraint<"input", "result">]> {
  let arguments = (ins FIRRTLType:$input);
  let results = (outs PassiveType:$result);

  let hasFolder = 1;
  let assemblyFormat = "$input attr-dict `:` type($input)";

  let builders = [
    OpBuilderDAG<(ins "Value":$input)>
  ];
}

// Convert a passive value to a non-passive type.
def AsNonPassivePrimOp : FIRRTLOp<"asNonPassive", [NoSideEffect,
                                  PassiveConstraint<"result", "input">]> {
  let arguments = (ins PassiveType:$input);
  let results = (outs FIRRTLType:$result);

  let hasFolder = 1;
  let assemblyFormat = "$input attr-dict `:` type($result)";
}
