module num_types
  integer, parameter :: qp = selected_real_kind(32)
  integer, parameter :: dp = kind(0.0d0)
  integer, parameter :: sp = kind(0.0)
  !> Global precision used in computations
  integer, parameter :: rp = kind(0.0d0)
end module num_types
