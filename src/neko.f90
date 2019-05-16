!> Master module
!
module neko
  use num_types
  use utils
  use math
  use speclib
  use space
  use htable
  use generic_file
  use entity
  use point
  use element
  use quad
  use hex
  use mesh
  use rea
  use vtk_file
  use file
  use field
  use mpi
  use mpi_types
contains

  subroutine neko_init
    integer :: ierr

    call MPI_Init(ierr)

    call mpi_types_init

    call MPI_Barrier(MPI_COMM_WORLD, ierr)
  end subroutine neko_init

end module neko
