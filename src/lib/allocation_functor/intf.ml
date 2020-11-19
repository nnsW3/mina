open Core_kernel

module Partial = struct
  module type Bin_io_intf = Binable.S

  module type Sexp_intf = Sexpable.S

  module type Yojson_intf = sig
    type t [@@deriving yojson]
  end
end

module type Creatable_intf = sig
  type t

  type 'a creator

  val create : t creator
end

module type Higher_order_creatable_intf = sig
  include Creatable_intf

  val map_creator : 'a creator -> f:('a -> 'b) -> 'b creator
end

module Input = struct
  module type Basic_intf = sig
    val id : string

    include Higher_order_creatable_intf
  end

  module type Bin_io_intf = sig
    include Basic_intf

    include Partial.Bin_io_intf with type t := t
  end

  module type Sexp_intf = sig
    include Basic_intf

    include Partial.Sexp_intf with type t := t
  end

  module type Yojson_intf = sig
    include Basic_intf

    include Partial.Yojson_intf with type t := t
  end

  module type Full_intf = sig
    include Basic_intf

    include Partial.Bin_io_intf with type t := t

    include Partial.Sexp_intf with type t := t

    include Partial.Yojson_intf with type t := t
  end
end

module Output = struct
  module type Basic_intf = Creatable_intf

  module type Bin_io_intf = sig
    include Basic_intf

    include Partial.Bin_io_intf with type t := t
  end

  module type Sexp_intf = sig
    include Basic_intf

    include Partial.Sexp_intf with type t := t
  end

  module type Yojson_intf = sig
    include Basic_intf

    include Partial.Yojson_intf with type t := t
  end

  module type Full_intf = sig
    include Basic_intf

    include Partial.Bin_io_intf with type t := t

    include Partial.Sexp_intf with type t := t

    include Partial.Yojson_intf with type t := t
  end
end