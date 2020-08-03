open Char

type shape = I8x16 | I16x8 | I32x4 | I64x2 | F32x4 | F64x2

let lanes shape =
  match shape with
  | I8x16 -> 16
  | I16x8 -> 8
  | I32x4 -> 4
  | I64x2 -> 2
  | F32x4 -> 4
  | F64x2 -> 2

module type RepType =
sig
  type t

  val make : int -> char -> t
  (* ^ bits_make ? *)
  val to_string : t -> string
  val bytewidth : int
  val of_strings : shape -> string list -> t

  val to_i8x16 : t -> I8.t list
  val of_i8x16 : I8.t list -> t

  val to_i16x8 : t -> I16.t list
  val of_i16x8 : I16.t list -> t

  val to_i32x4 : t -> I32.t list
  val of_i32x4 : I32.t list -> t

  val to_i64x2 : t -> I64.t list
  val of_i64x2 : I64.t list -> t

  val to_f32x4 : t -> F32.t list
  val of_f32x4 : F32.t list -> t

  val to_f64x2 : t -> F64.t list
  val of_f64x2 : F64.t list -> t
end

(* This signature defines the types and operations SIMD ints can expose. *)
module type Int =
sig
  type t
  type lane

  val splat : lane -> t
  val extract_lane_s : int -> t -> lane
  val extract_lane_u : int -> t -> lane
  val eq : t -> t -> t
  val ne : t -> t -> t
  val lt_s : t -> t -> t
  val lt_u : t -> t -> t
  val le_s : t -> t -> t
  val le_u : t -> t -> t
  val gt_s : t -> t -> t
  val gt_u : t -> t -> t
  val ge_s : t -> t -> t
  val ge_u : t -> t -> t
  val abs : t -> t
  val neg : t -> t
  val add : t -> t -> t
  val sub : t -> t -> t
  val min_s : t -> t -> t
  val min_u : t -> t -> t
  val max_s : t -> t -> t
  val max_u : t -> t -> t
  val mul : t -> t -> t
  val avgr_u : t -> t -> t
  val any_true : t -> bool
  val all_true : t -> bool
  val shl : t -> I32.t -> t
  val shr_s : t -> I32.t -> t
end

(* This signature defines the types and operations SIMD floats can expose. *)
module type Float =
sig
  type t
  type lane

  val splat : lane -> t
  val extract_lane : int -> t -> lane
  val eq : t -> t -> t
  val ne : t -> t -> t
  val lt : t -> t -> t
  val le : t -> t -> t
  val gt : t -> t -> t
  val ge : t -> t -> t
  val abs : t -> t
  val neg : t -> t
  val sqrt : t -> t
  val add : t -> t -> t
  val sub : t -> t -> t
  val mul : t -> t -> t
  val div : t -> t -> t
  val min : t -> t -> t
  val max : t -> t -> t
end

module type Vec =
sig
  type t

  val lognot : t -> t
  val and_ : t -> t -> t
  val or_ : t -> t -> t
  val xor : t -> t -> t
  val andnot : t -> t -> t
  val bitselect : t -> t -> t -> t
end

module type S =
sig
  type t
  type bits
  val default : t (* FIXME good name for default value? *)
  val to_string : t -> string
  val of_bits : bits -> t
  val to_bits : t -> bits
  val of_strings : shape -> string list -> t
  val to_i16x8 : t -> I16.t list
  val to_i32x4 : t -> I32.t list

  (* We need type t = t to ensure that all submodule types are S.t,
   * then callers don't have to change *)
  module I8x16 : Int with type t = t and type lane = I8.t
  module I16x8 : Int with type t = t and type lane = I16.t
  module I32x4 : Int with type t = t and type lane = I32.t
  module I64x2 : Int with type t = t and type lane = I64.t
  module F32x4 : Float with type t = t and type lane = F32.t
  module F64x2 : Float with type t = t and type lane = F64.t
  module V128 : Vec with type t = t
end

module Make (Rep : RepType) : S with type bits = Rep.t =
struct
  type t = Rep.t
  type bits = Rep.t

  let default = Rep.make Rep.bytewidth (chr 0)
  let to_string = Rep.to_string (* FIXME very very wrong *)
  let of_bits x = x
  let to_bits x = x
  let of_strings = Rep.of_strings
  let to_i16x8 = Rep.to_i16x8
  let to_i32x4 = Rep.to_i32x4

  module V128 : Vec with type t = Rep.t = struct
    type t = Rep.t
    let to_shape = Rep.to_i64x2
    let of_shape = Rep.of_i64x2
    let unop f x = of_shape (List.map f (to_shape x))
    let binop f x y = of_shape (List.map2 f (to_shape x) (to_shape y))
    let lognot = unop I64.lognot
    let and_ = binop I64.and_
    let or_ = binop I64.or_
    let xor = binop I64.xor
    let andnot = binop (fun x y -> I64.and_ x (I64.lognot y))
    let bitselect v1 v2 c =
      let v2_andnot_c = andnot v2 c in
      let v1_and_c = binop I64.and_ v1 c in
      binop I64.or_ v1_and_c v2_andnot_c
  end


  module MakeFloat (Float : Float.S) (Convert : sig
      val to_shape : Rep.t -> Float.t list
      val of_shape : Float.t list -> Rep.t
      val num_lanes : int
    end) : Float with type t = Rep.t and type lane = Float.t =
  struct
    type t = Rep.t
    type lane = Float.t
    let unop f x = Convert.of_shape (List.map f (Convert.to_shape x))
    let binop f x y = Convert.of_shape (List.map2 f (Convert.to_shape x) (Convert.to_shape y))
    let all_ones = Float.of_float (Int64.float_of_bits (Int64.minus_one))
    let cmp f x y = if f x y then all_ones else Float.zero
    let eq = binop (cmp Float.eq)
    let ne = binop (cmp Float.ne)
    let lt = binop (cmp Float.lt)
    let le = binop (cmp Float.le)
    let gt = binop (cmp Float.gt)
    let ge = binop (cmp Float.ge)
    let abs = unop Float.abs
    let neg = unop Float.neg
    let sqrt = unop Float.sqrt
    let add = binop Float.add
    let sub = binop Float.sub
    let mul = binop Float.mul
    let div = binop Float.div
    let min = binop Float.min
    let max = binop Float.max
    let splat x = Convert.of_shape (List.init Convert.num_lanes (fun i -> x))
    let extract_lane i s = List.nth (Convert.to_shape s) i
  end

  module MakeInt (Int : Int.S) (Convert : sig
      val to_shape : Rep.t -> Int.t list
      val of_shape : Int.t list -> Rep.t
      val num_lanes : int
    end) : Int with type t = Rep.t and type lane = Int.t =
  struct
    type t = Rep.t
    type lane = Int.t
    let splat x = Convert.of_shape (List.init Convert.num_lanes (fun i -> x))
    let extract_lane_s i s = List.nth (Convert.to_shape s) i
    let extract_lane_u i s = Int.as_unsigned (extract_lane_s i s)
    let unop f x = Convert.of_shape (List.map f (Convert.to_shape x))
    let binop f x y = Convert.of_shape (List.map2 f (Convert.to_shape x) (Convert.to_shape y))
    let cmp f x y = if f x y then (Int.of_int_s (-1)) else Int.zero
    let eq = binop (cmp Int.eq)
    let ne = binop (cmp Int.ne)
    let lt_s = binop (cmp Int.lt_s)
    let lt_u = binop (cmp Int.lt_u)
    let le_s = binop (cmp Int.le_s)
    let le_u = binop (cmp Int.le_u)
    let gt_s = binop (cmp Int.gt_s)
    let gt_u = binop (cmp Int.gt_u)
    let ge_s = binop (cmp Int.ge_s)
    let ge_u = binop (cmp Int.ge_u)
    let abs = unop Int.abs
    let neg = unop Int.neg
    let add = binop Int.add
    let sub = binop Int.sub
    let mul = binop Int.mul
    let choose f x y = if f x y then x else y
    let min_s = binop (choose Int.le_s)
    let min_u = binop (choose Int.le_u)
    let max_s = binop (choose Int.ge_s)
    let max_u = binop (choose Int.ge_u)
    (* The result of avgr_u will not overflow this type, but the intermediate might,
     * so have the Int type implement it so they can extend it accordingly *)
    let avgr_u = binop Int.avgr_u
    let reduceop f a s = List.fold_left (fun a b -> f a (b <> Int.zero)) a (Convert.to_shape s)
    let any_true = reduceop (||) false
    let all_true = reduceop (&&) true
    let shl v s =
      let shift = Int.of_int_u (Int32.to_int s) in
      unop (fun a -> Int.shl a shift) v
    let shr_s v s =
      let shift = Int.of_int_u (Int32.to_int s) in
      unop (fun a -> Int.shr_s a shift) v
  end

  module I8x16 = MakeInt (I8) (struct
      let to_shape = Rep.to_i8x16
      let of_shape = Rep.of_i8x16
      let num_lanes = lanes I8x16
    end)

  module I16x8 = MakeInt (I16) (struct
      let to_shape = Rep.to_i16x8
      let of_shape = Rep.of_i16x8
      let num_lanes = lanes I16x8
    end)

  module I32x4 = MakeInt (I32) (struct
      let to_shape = Rep.to_i32x4
      let of_shape = Rep.of_i32x4
      let num_lanes = lanes I32x4
    end)

  module I64x2 = MakeInt (I64) (struct
      let to_shape = Rep.to_i64x2
      let of_shape = Rep.of_i64x2
      let num_lanes = lanes I64x2
    end)

  module F32x4 = MakeFloat (F32) (struct
      let to_shape = Rep.to_f32x4
      let of_shape = Rep.of_f32x4
      let num_lanes = lanes F32x4
    end)

  module F64x2 = MakeFloat (F64) (struct
      let to_shape = Rep.to_f64x2
      let of_shape = Rep.of_f64x2
      let num_lanes = lanes F64x2
    end)

end