//===- RTLAggregates.td - RTL ops for structs/arrays/etc ---*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This describes the MLIR ops for working with aggregate values like structs
// and arrays.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Packed Array Processing Operations
//===----------------------------------------------------------------------===//

def ArrayCreateOp : RTLOp<"array_create", [NoSideEffect, SameTypeOperands]> {
  let summary = "Create an array from values";
  let description = [{
    Creates an array from a variable set of values. One or more values must be
    listed.

    ```
    // %a, %b, %c are all i4
    %array = rtl.array_create %a, %b, %c : (i4)
    ```
  }];

  let arguments = (ins Variadic<RTLNonInOutType>:$inputs);
  let results = (outs ArrayType:$result);

  let verifier = [{
    unsigned returnSize = getType().cast<ArrayType>().getSize();
    if (inputs().size() != returnSize)
      return failure();
    return success();
  }];

  let printer = "return ::print(p, *this);";
  let parser = "return ::parse$cppClass(parser, result);";
  let builders = [
    // ArrayRef needs to contain at least one element.
    OpBuilderDAG<(ins "ArrayRef<::mlir::Value>":$input)>
  ];
}

def ArraySliceOp : RTLOp<"array_slice", [NoSideEffect]> {
  let summary = "Get a range of values from an array";
  let description = [{
    Extracts a sub-range from an array. The range is from `lowIndex` to
    `lowIndex` + the number of elements in the return type, non-inclusive on
    the high end. For instance,

    ```
    // Slices 16 elements starting at '%offset'.
    %subArray = rtl.slice %largerArray at %offset :
        (!rtl.array<1024xi8>) -> !rtl.array<16xi8>
    ```

    Would translate to the following SystemVerilog:

    ```
    logic [7:0][15:0] subArray = largerArray[offset +: 16];
    ```

    Width of 'idx' is defined to be the precise number of bits required to
    index the 'input' array. More precisely: for an input array of size M,
    the width of 'idx' is ceil(log2(M)). Lower and upper bound indexes which
    are larger than the size of the 'input' array results in undefined
    behavior.
  }];

  let arguments = (ins ArrayType:$input, RTLIntegerType:$lowIndex);
  let results = (outs ArrayType:$dst);
  let verifier = [{
    unsigned inputSize = input().getType().cast<ArrayType>().getSize();
    if (llvm::Log2_64_Ceil(inputSize) !=
          lowIndex().getType().getIntOrFloatBitWidth())
      return emitOpError(
        "ArraySlice: index width must match clog2 of array size");
    return success();
  }];

  let assemblyFormat = [{
    $input `at` $lowIndex attr-dict `:`
      `(` custom<SliceTypes>(type($input), type($lowIndex)) `)` `->` type($dst)
  }];

  let builders = [
    OpBuilderDAG<(ins "Value":$input, "size_t":$lowBit, "size_t":$size)>
  ];
}

class IndexBitWidthConstraint<string index, string input>
  : TypesMatchWith<"Index width should be exactly clog2 (size of array)",
                   input, index,
                   [{
    IntegerType::get($_self.getContext(),
                     llvm::Log2_64_Ceil($_self.cast<ArrayType>().getSize()))
                   }]>;

class ArrayElementTypeConstraint<string result, string input>
  : TypesMatchWith<"Result must be arrays element type",
                   input, result,
                   "$_self.cast<ArrayType>().getElementType()">;

// rtl.array_get does not work with unpacked arrays.
def ArrayGetOp : RTLOp<"array_get",
    [NoSideEffect, IndexBitWidthConstraint<"index", "input">,
     ArrayElementTypeConstraint<"result", "input">]> {
  let summary = "Get the value in an array at the specified index";
  let arguments = (ins ArrayType:$input, RTLIntegerType:$index);
  let results = (outs RTLNonInOutType:$result);

  let assemblyFormat = [{
    $input`[`$index`]` attr-dict `:` type($input)
  }];

  let builders = [
    OpBuilderDAG<(ins "Value":$input, "Value":$index)>
  ];
}

//===----------------------------------------------------------------------===//
// Structure Processing Operations
//===----------------------------------------------------------------------===//

def StructCreateOp : RTLOp<"struct_create", [NoSideEffect]> {
  let summary = "Create a struct from constituent parts.";
  let arguments = (ins Variadic<RTLNonInOutType>:$input);
  let results = (outs StructType:$result);

  let parser = "return ::parse$cppClass(parser, result);";
  let printer = "return ::print(p, *this);";
}

// Extract a range of bits from the specified input.
def StructExtractOp : RTLOp<"struct_extract", [NoSideEffect]> {
  let summary = "Extract a named field from a struct.";

  let arguments = (ins StructType:$input, StrAttr:$field);
  let results = (outs RTLNonInOutType:$result);

  let parser = "return ::parse$cppClass(parser, result);";
  let printer = "return ::print(p, *this);";
}

// Extract a range of bits from the specified input.
def StructInjectOp : RTLOp<"struct_inject", [NoSideEffect, 
                           AllTypesMatch<["input", "result"]>]> {
  let summary = "Inject a value into a named field of a struct.";

  let arguments = (ins StructType:$input, StrAttr:$field,
                   RTLNonInOutType:$newValue);
  let results = (outs StructType:$result);

  let parser = "return ::parse$cppClass(parser, result);";
  let printer = "return ::print(p, *this);";
}

def StructExplodeOp : RTLOp<"struct_explode", [NoSideEffect]> {
  let summary = "Expand a struct into its constituent parts.";
  let arguments = (ins StructType:$input);
  let results = (outs Variadic<RTLNonInOutType>:$result);

  let parser = "return ::parse$cppClass(parser, result);";
  let printer = "return ::print(p, *this);";
}
