!> Defines a mapping of the degrees of freedom
!! @details A mapping defined based on a function space and a mesh
module dofmap
  use mesh
  use space
  use tuple
  implicit none
  private

  type, public :: dofmap_t
     integer(kind=8), allocatable :: dof(:,:,:,:) !< Mapping to unique dof
     logical, allocatable :: shared_dof(:,:,:,:)  !< True if the dof is shared
     type(mesh_t), pointer :: msh
     type(space_t), pointer :: Xh
   contains
     final :: dofmap_free
  end type dofmap_t

  interface dofmap_t
     module procedure dofmap_init
  end interface dofmap_t
  
contains

  function dofmap_init(msh, Xh) result(this)
    type(mesh_t), target, intent(inout) :: msh !< Mesh
    type(space_t), target, intent(in) :: Xh !< Function space \f$ X_h \f$
    type(dofmap_t) :: this
    type(tuple_i4_t) :: edge
    type(tuple4_i4_t) :: face
    integer :: i,j,k,l
    integer(kind=8) :: num_dofs_edges(3) ! #dofs for each dir (r, s, t)
    integer(kind=8) :: num_dofs_faces(3) ! #dofs for each dir (r, s, t)
    integer :: global_id
    integer(kind=8) :: edge_id, edge_offset, facet_offset, facet_id
    logical :: shared_dof
    
    call dofmap_free(this)

    this%msh => msh
    this%Xh => Xh
        
    allocate(this%dof(Xh%lx, Xh%ly, Xh%lz, msh%nelv))
    allocate(this%shared_dof(Xh%lx, Xh%ly, Xh%lz, msh%nelv))

    this%dof = 0
    this%shared_dof = .false.

    !> @todo implement for 2d elements

    ! Assign numbers to each dofs on points
    do i = 1, msh%nelv
       this%dof(1, 1, 1, i) = &
            int(msh%elements(i)%e%pts(1)%p%id(), 8)
       this%dof(Xh%lx, 1, 1, i) = &
            int(msh%elements(i)%e%pts(2)%p%id(), 8)
       this%dof(1, Xh%ly, 1, i) = &
            int(msh%elements(i)%e%pts(4)%p%id(), 8)
       this%dof(Xh%lx, Xh%ly, 1, i) = &
            int(msh%elements(i)%e%pts(3)%p%id(), 8)

       this%dof(1, 1, Xh%lz, i) = &
            int(msh%elements(i)%e%pts(5)%p%id(), 8)
       this%dof(Xh%lx, 1, Xh%lz, i) = &
            int(msh%elements(i)%e%pts(6)%p%id(), 8)
       this%dof(1, Xh%ly, Xh%lz, i) = &
            int(msh%elements(i)%e%pts(8)%p%id(), 8)
       this%dof(Xh%lx, Xh%ly, Xh%lz, i) = &
            int(msh%elements(i)%e%pts(7)%p%id(), 8)

       this%shared_dof(1, 1, 1, i) = &
            mesh_is_shared(msh, msh%elements(i)%e%pts(1)%p)
       
       this%shared_dof(Xh%lx, 1, 1, i) = &
            mesh_is_shared(msh, msh%elements(i)%e%pts(2)%p)

       this%shared_dof(1, Xh%ly, 1, i) = &
            mesh_is_shared(msh, msh%elements(i)%e%pts(4)%p)
       
       this%shared_dof(Xh%lx, Xh%ly, 1, i) = &
            mesh_is_shared(msh, msh%elements(i)%e%pts(3)%p)

       this%shared_dof(1, 1, Xh%lz, i) = &
            mesh_is_shared(msh, msh%elements(i)%e%pts(5)%p)
       
       this%shared_dof(Xh%lx, 1, Xh%lz, i) = &
            mesh_is_shared(msh, msh%elements(i)%e%pts(6)%p)

       this%shared_dof(1, Xh%ly, Xh%lz, i) = &
            mesh_is_shared(msh, msh%elements(i)%e%pts(8)%p)
       
       this%shared_dof(Xh%lx, Xh%ly, Xh%lz, i) = &
            mesh_is_shared(msh, msh%elements(i)%e%pts(7)%p)
       
    end do
    
    !
    ! Assign numbers to dofs on edges
    !

    ! Number of dofs on an edge excluding end-points
    num_dofs_edges(1) =  int(Xh%lx - 2, 8)
    num_dofs_edges(2) =  int(Xh%ly - 2, 8)
    num_dofs_edges(3) =  int(Xh%lz - 2, 8)

    edge_offset = int(msh%glb_mpts, 8) + int(1, 8)

    do i = 1, msh%nelv
       
       select type(ep=>msh%elements(i)%e)
       type is (hex_t)

          !
          ! Number edges in x-direction
          ! 
          call ep%edge_id(edge, 1)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(1)
          do j = 2, Xh%lx - 1
             this%dof(j, 1, 1, i) = edge_id
             this%shared_dof(j, 1, 1, i) = shared_dof
             edge_id = edge_id + 1
          end do
          
          call ep%edge_id(edge, 3)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(1)
          do j = 2, Xh%lx - 1
             this%dof(j, 1, Xh%lz, i) = edge_id
             this%shared_dof(j, 1, Xh%lz, i) = shared_dof
             edge_id = edge_id + 1
          end do

          call ep%edge_id(edge, 2)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(1)
          do j = 2, Xh%lx - 1
             this%dof(j, Xh%ly, 1, i) = edge_id
             this%shared_dof(j, Xh%ly, 1, i) = shared_dof
             edge_id = edge_id + 1
          end do

          call ep%edge_id(edge, 4)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(1)
          do j = 2, Xh%lx - 1
             this%dof(j, Xh%ly, Xh%lz, i) = edge_id
             this%shared_dof(j, Xh%ly, Xh%lz, i) = shared_dof
             edge_id = edge_id + 1
          end do


          !
          ! Number edges in y-direction
          ! 
          call ep%edge_id(edge, 5)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(2)
          do j = 2, Xh%ly - 1
             this%dof(1, j, 1, i) = edge_id
             this%shared_dof(1, j, 1, i) = shared_dof
             edge_id = edge_id + 1
          end do
          
          call ep%edge_id(edge, 7)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(2)
          do j = 2, Xh%ly - 1
             this%dof(1, j, Xh%lz, i) = edge_id
             this%shared_dof(1, j, Xh%lz, i) = shared_dof
             edge_id = edge_id + 1
          end do

          call ep%edge_id(edge, 6)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(2)
          do j = 2, Xh%ly - 1
             this%dof(Xh%lx, j, 1, i) = edge_id
             this%shared_dof(Xh%lx, j, 1, i) = shared_dof
             edge_id = edge_id + 1
          end do

          call ep%edge_id(edge, 8)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(2)
          do j = 2, Xh%ly - 1
             this%dof(Xh%lx, j, Xh%lz, i) = edge_id
             this%shared_dof(Xh%lx, j, Xh%lz, i) = shared_dof
             edge_id = edge_id + 1
          end do

          !
          ! Number edges in z-direction
          ! 
          call ep%edge_id(edge, 9)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(3)
          do j = 2, Xh%lz - 1
             this%dof(1, 1, j, i) = edge_id
             this%shared_dof(1, 1, j, i) = shared_dof
             edge_id = edge_id + 1
          end do
          
          call ep%edge_id(edge, 10)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(3)
          do j = 2, Xh%lz - 1
             this%dof(Xh%lx, 1, j, i) = edge_id
             this%shared_dof(Xh%lx, 1, j, i) = shared_dof
             edge_id = edge_id + 1
          end do

          call ep%edge_id(edge, 11)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(3)
          do j = 2, Xh%lz - 1
             this%dof(1, Xh%ly, j, i) = edge_id
             this%shared_dof(1, Xh%ly, j, i) = shared_dof
             edge_id = edge_id + 1
          end do

          call ep%edge_id(edge, 12)
          shared_dof = mesh_is_shared(msh, edge)
          global_id = mesh_get_global(msh, edge)
          edge_id = edge_offset + int((global_id - 1), 8) * num_dofs_edges(3)
          do j = 2, Xh%lz - 1
             this%dof(Xh%lx, Xh%ly, j, i) = edge_id
             this%shared_dof(Xh%lx, Xh%ly, j, i) = shared_dof
             edge_id = edge_id + 1
          end do
          
       end select
       
    end do

    ! Assign numbers to dofs on facets

    !> @todo don't assume lx = ly = lz
    facet_offset = int(msh%glb_mpts, 8) + &
         int(msh%glb_meds, 8) * int(Xh%lx-2, 8)

    ! Number of dofs on an edge excluding end-points
    num_dofs_faces(1) =  int((Xh%ly - 2) * (Xh%lz - 2), 8)
    num_dofs_faces(2) =  int((Xh%lx - 2) * (Xh%lz - 2), 8)
    num_dofs_faces(3) =  int((Xh%lx - 2) * (Xh%ly - 2), 8)

    do i = 1, msh%nelv
       
       !
       ! Number facets in x-direction (s, t)-plane
       !
       call msh%elements(i)%e%facet_id(face, 1)
       shared_dof = mesh_is_shared(msh, face)
       global_id = mesh_get_global(msh, face)
       facet_id = facet_offset + int((global_id - 1), 8) * num_dofs_edges(1)
       do k = 2, Xh%lz -1
          do j = 2, Xh%ly - 1
             this%dof(1, j, k, i) = facet_id
             this%shared_dof(1, j, k, i) = shared_dof
             facet_id = facet_id + 1
          end do
       end do
       
       call msh%elements(i)%e%facet_id(face, 2)
       shared_dof = mesh_is_shared(msh, face)
       global_id = mesh_get_global(msh, face)
       facet_id = facet_offset + int((global_id - 1), 8) * num_dofs_edges(1)
       do k = 2, Xh%lz -1
          do j = 2, Xh%ly - 1
             this%dof(Xh%lx, j, k, i) = facet_id
             this%shared_dof(Xh%lx, j, k, i) = shared_dof
             facet_id = facet_id + 1
          end do
       end do


       !
       ! Number facets in y-direction (r, t)-plane
       !
       call msh%elements(i)%e%facet_id(face, 3)
       shared_dof = mesh_is_shared(msh, face)
       global_id = mesh_get_global(msh, face)
       facet_id = facet_offset + int((global_id - 1), 8) * num_dofs_edges(2)
       do k = 2, Xh%lz - 1
          do j = 2, Xh%lx - 1
             this%dof(j, 1, k, i) = facet_id
             this%shared_dof(j, 1, k, i) = shared_dof
             facet_id = facet_id + 1
          end do
       end do
       
       call msh%elements(i)%e%facet_id(face, 4)
       shared_dof = mesh_is_shared(msh, face)
       global_id = mesh_get_global(msh, face)
       facet_id = facet_offset + int((global_id - 1), 8) * num_dofs_edges(2)
       do k = 2, Xh%lz - 1
          do j = 2, Xh%lx - 1
             this%dof(j, Xh%ly, k, i) = facet_id
             this%shared_dof(j, Xh%ly, k, i) = shared_dof
             facet_id = facet_id + 1
          end do
       end do


       !
       ! Number facets in z-direction (r, s)-plane
       !
       call msh%elements(i)%e%facet_id(face, 5)
       shared_dof = mesh_is_shared(msh, face)
       global_id = mesh_get_global(msh, face)
       facet_id = facet_offset + int((global_id - 1), 8) * num_dofs_edges(3)
       do k = 2, Xh%ly - 1
          do j = 2, Xh%lx - 1
             this%dof(j, k, 1, i) = facet_id
             this%shared_dof(j, k, 1, i) = shared_dof
             facet_id = facet_id + 1
          end do
       end do
       
       call msh%elements(i)%e%facet_id(face, 6)
       shared_dof = mesh_is_shared(msh, face)
       global_id = mesh_get_global(msh, face)
       facet_id = facet_offset + int((global_id - 1), 8) * num_dofs_edges(3)
       do k = 2, Xh%lz - 1
          do j = 2, Xh%lx - 1
             this%dof(j, k, Xh%lz, i) = facet_id
             this%shared_dof(j, k, Xh%lz, i) = shared_dof
             facet_id = facet_id + 1
          end do
       end do
    end do

  end function dofmap_init


  subroutine dofmap_free(this)
    type(dofmap_t), intent(inout) :: this

    if (allocated(this%dof)) then
       deallocate(this%dof)
    end if

    if (allocated(this%shared_dof)) then
       deallocate(this%shared_dof)
    end if

    nullify(this%msh)
    nullify(this%Xh)
    
  end subroutine dofmap_free
  
end module dofmap