!> NEKTON mesh data in re2 format
!! @details This module is used to read/write binary NEKTION mesh data
module re2_file
  use generic_file
  use num_types
  use utils
  use mesh
  use point
  use comm
  use mpi_f08
  use mpi_types
  use datadist
  use re2
  use map
  use map_file
  use htable
  implicit none
  private
  

  !> Interface for NEKTON re2 files
  type, public, extends(generic_file_t) :: re2_file_t
   contains
     procedure :: read => re2_file_read
     procedure :: write => re2_file_write
  end type re2_file_t

contains

  !> Load a binary NEKTON mesh from a re2 file
  subroutine re2_file_read(this, data)
    class(re2_file_t) :: this
    class(*), target, intent(inout) :: data
    type(mesh_t), pointer :: msh
    character(len=5) :: hdr_ver
    character(len=54) :: hdr_str
    integer :: i, j, k, nel, ndim, nelv, ierr, pt_idx, el_idx
    type(MPI_Status) :: status
    type(MPI_File) :: fh
    integer (kind=MPI_OFFSET_KIND) :: mpi_offset
    real(kind=sp) :: test
    real(kind=dp) :: t2
    integer :: ncurv, nbcs
    type(linear_dist_t) :: dist
    type(map_t) :: nm
    type(map_file_t) :: map_file
    character(len=80) :: map_fname
    logical :: read_map
    integer :: re2_data_xy_size
    integer :: re2_data_xyz_size
    integer :: re2_data_cv_size
    integer :: re2_data_bc_size
    logical :: v2_format

    
    select type(data)
    type is (mesh_t)
       msh => data
    class default
       call neko_error('Invalid output data')
    end select

    v2_format = .false.
    open(unit=9,file=trim(this%fname), status='old', iostat=ierr)
    if (pe_rank .eq. 0) then
       write(*, '(A,A)') " Reading binary NEKTON file ", this%fname
    end if
    read(9, '(a5,i9,i3,i9,a54)') hdr_ver, nel, ndim, nelv, hdr_str
    if (hdr_ver .eq. '#v002') then
       v2_format = .true.
       call MPI_Type_size(MPI_RE2V2_DATA_XY, re2_data_xy_size, ierr)
       call MPI_Type_size(MPI_RE2V2_DATA_XYZ, re2_data_xyz_size, ierr)
       call MPI_Type_size(MPI_RE2V2_DATA_CV, re2_data_cv_size, ierr)
       call MPI_Type_size(MPI_RE2V2_DATA_BC, re2_data_bc_size, ierr)
    else
       call MPI_Type_size(MPI_RE2V1_DATA_XY, re2_data_xy_size, ierr)
       call MPI_Type_size(MPI_RE2V1_DATA_XYZ, re2_data_xyz_size, ierr)
       call MPI_Type_size(MPI_RE2V1_DATA_CV, re2_data_cv_size, ierr)
       call MPI_Type_size(MPI_RE2V1_DATA_BC, re2_data_bc_size, ierr)    
    end if

    if (pe_rank .eq. 0) write(*,1) ndim, nelv
1   format(1x,'ndim = ', i1, ', nelements =', i7)
    close(9)

    call filename_chsuffix(this%fname, map_fname,'map')

    inquire(file=map_fname, exist=read_map)
    if (read_map) then
       call map_init(nm, nelv, 2**ndim)
       call map_file%init(map_fname)
       call map_file%read(nm)
    else
       if (pe_rank .eq. 0) call neko_warning('No NEKTON map file found')
    end if

    call MPI_File_open(NEKO_COMM, trim(this%fname), &
         MPI_MODE_RDONLY, MPI_INFO_NULL, fh, ierr)
    
    if (ierr .ne. 0) then
       call neko_error("Can't open binary NEKTON file ")
    end if
    dist = linear_dist_t(nelv, pe_rank, pe_size, NEKO_COMM)

    call mesh_init(msh, ndim, dist)

    ! Set offset (header)
    mpi_offset = RE2_HDR_SIZE * MPI_CHARACTER_SIZE

    call MPI_File_read_at_all(fh, mpi_offset, test, 1, MPI_REAL, status, ierr)
    mpi_offset = mpi_offset + MPI_REAL_SIZE
    
    if (abs(RE2_ENDIAN_TEST - test) .gt. 1e-4) then
       call neko_error('Invalid endian of re2 file, byte swap not implemented yet')
    end if

    call re2_file_read_points(msh, ndim, nel, dist, fh, &
         mpi_offset, re2_data_xy_size, re2_data_xyz_size, v2_format)
    
          
    ! Set offset to start of curved side data
    mpi_offset = RE2_HDR_SIZE * MPI_CHARACTER_SIZE + MPI_REAL_SIZE
    if (ndim .eq. 2) then
       mpi_offset = mpi_offset + dist%num_global() * re2_data_xy_size
    else
       mpi_offset = mpi_offset + dist%num_global() * re2_data_xyz_size
    end if

    !> @todo Add support for curved side data
    !! Skip curved side data
    call MPI_File_read_at_all(fh, mpi_offset, ncurv, 1, MPI_INTEGER, status, ierr)
    mpi_offset = mpi_offset + MPI_INTEGER_SIZE 
    call re2_file_read_curve(msh, ncurv, dist, fh, mpi_offset, v2_format)
    mpi_offset = mpi_offset + ncurv * re2_data_cv_size

    call MPI_File_read_at_all(fh, mpi_offset, nbcs, 1, MPI_INTEGER, status, ierr)
    mpi_offset = mpi_offset + MPI_INTEGER_SIZE

    call re2_file_read_bcs(msh, nbcs, dist, fh, mpi_offset, v2_format)

    call MPI_FILE_close(fh, ierr)
    call mesh_finalize(msh)


    if (pe_rank .eq. 0) write(*,*) 'Done'

    
  end subroutine re2_file_read

  subroutine re2_file_write(this, data, t)
    class(re2_file_t), intent(inout) :: this
    class(*), target, intent(in) :: data
    real(kind=rp), intent(in), optional :: t
    type(re2v1_xy_t), allocatable :: re2_data_xy(:)
    type(re2v1_xyz_t), allocatable :: re2_data_xyz(:)
    type(mesh_t), pointer :: msh
    character(len=5), parameter :: RE2_HDR_VER = '#v001'
    character(len=54), parameter :: RE2_HDR_STR = 'RE2 exported by NEKO'
    integer :: i, j, k, ierr, pt_idx, nelgv
    type(MPI_Status) :: status
    type(MPI_File) :: fh    
    integer (kind=MPI_OFFSET_KIND) :: mpi_offset
    integer :: element_offset
    integer :: re2_data_xy_size
    integer :: re2_data_xyz_size
        
    select type(data)
    type is (mesh_t)
       msh => data
    class default
       call neko_error('Invalid output data')
    end select

    call MPI_Type_size(MPI_RE2V1_DATA_XY, re2_data_xy_size, ierr)
    call MPI_Type_size(MPI_RE2V1_DATA_XYZ, re2_data_xyz_size, ierr)
    call MPI_Reduce(msh%nelv, nelgv, 1, &
         MPI_INTEGER, MPI_SUM, 0, NEKO_COMM, ierr)
    element_offset = 0
    call MPI_Exscan(msh%nelv, element_offset, 1, &
         MPI_INTEGER, MPI_SUM, NEKO_COMM, ierr)

    if (pe_rank .eq. 0) then
       open(unit=9,file=trim(this%fname), status='new', iostat=ierr)
       write(*, '(A,A)') " Writing data as a binary NEKTON file ", this%fname
       write(9, '(a5,i9,i3,i9,a54)') RE2_HDR_VER, nelgv, msh%gdim,&
            nelgv, RE2_HDR_STR
       close(9)
    end if

    call MPI_Barrier(NEKO_COMM, ierr)
    call MPI_File_open(NEKO_COMM, trim(this%fname), &
         MPI_MODE_WRONLY + MPI_MODE_CREATE, MPI_INFO_NULL, fh, ierr)
    mpi_offset = RE2_HDR_SIZE * MPI_CHARACTER_SIZE
    
    call MPI_File_write_at(fh, mpi_offset, RE2_ENDIAN_TEST, 1, &
         MPI_REAL, status, ierr)
    mpi_offset = mpi_offset + MPI_REAL_SIZE

    if (msh%gdim .eq. 2) then
       allocate(re2_data_xy(msh%nelv))
       do i = 1, msh%nelv
          re2_data_xy(i)%rgroup = 1.0 ! Not used
          do j = 1, 4
             re2_data_xy(i)%x(j) = real(msh%elements(i)%e%pts(j)%p%x(1))
             re2_data_xy(i)%y(j) = real(msh%elements(i)%e%pts(j)%p%x(2))
          end do
       end do
       mpi_offset = mpi_offset + element_offset * re2_data_xy_size
       call MPI_File_write_at(fh, mpi_offset, &
            re2_data_xy, msh%nelv, MPI_RE2V1_DATA_XY, status, ierr)

       deallocate(re2_data_xy)

    else if (msh%gdim .eq. 3) then
       allocate(re2_data_xyz(msh%nelv))
       do i = 1, msh%nelv
          re2_data_xyz(i)%rgroup = 1.0 ! Not used
          do j = 1, 8 
             re2_data_xyz(i)%x(j) = real(msh%elements(i)%e%pts(j)%p%x(1))
             re2_data_xyz(i)%y(j) = real(msh%elements(i)%e%pts(j)%p%x(2))
             re2_data_xyz(i)%z(j) = real(msh%elements(i)%e%pts(j)%p%x(3))
          end do
       end do
       mpi_offset = mpi_offset + element_offset * re2_data_xyz_size
       call MPI_File_write_at(fh, mpi_offset, &
            re2_data_xyz, msh%nelv, MPI_RE2V1_DATA_XYZ, status, ierr)
       
       deallocate(re2_data_xyz)
    else
       call neko_error("Invalid dimension of mesh")
    end if
        
    call MPI_FILE_close(fh, ierr)
    write(*,*) 'Done'

    !> @todo Add support for curved side data
    
  end subroutine re2_file_write

  subroutine re2_file_read_points(msh, ndim, nel, dist, fh, &
       mpi_offset, re2_data_xy_size, re2_data_xyz_size, v2_format)
    type(mesh_t), intent(inout) :: msh
    integer (kind=MPI_OFFSET_KIND) :: mpi_offset
    integer, intent(inout) :: ndim
    integer, intent(inout) :: nel
    type(MPI_File), intent(inout) :: fh
    integer, intent(in) :: re2_data_xy_size
    integer, intent(in) :: re2_data_xyz_size
    logical, intent(in) :: v2_format
    type(linear_dist_t) :: dist
    integer :: element_offset
    type(re2v1_xy_t), allocatable :: re2v1_data_xy(:)
    type(re2v1_xyz_t), allocatable :: re2v1_data_xyz(:)
    type(re2v2_xy_t), allocatable :: re2v2_data_xy(:)
    type(re2v2_xyz_t), allocatable :: re2v2_data_xyz(:)
    type(MPI_Status) :: status
    type(htable_pt_t) :: htp
    type(point_t) :: p(8)
    integer :: pt_idx, nelv
    integer :: i, j, ierr

    
    nelv = dist%num_local()
    element_offset = dist%start_idx()

    call htp%init(2**ndim * nel, ndim)

    pt_idx = 0
    if (ndim .eq. 2) then
       mpi_offset = mpi_offset + element_offset * re2_data_xy_size          
       if (.not. v2_format) then
          allocate(re2v1_data_xy(nelv))
          call MPI_File_read_at_all(fh, mpi_offset, &
               re2v1_data_xy, nelv, MPI_RE2V1_DATA_XY, status, ierr)
          do i = 1, nelv
             do j = 1, 4             
                p(j) = point_t(real(re2v1_data_xy(i)%x(j),dp), &
                     real(re2v1_data_xy(i)%y(j),dp), 0.0d0)
                call re2_file_add_point(htp, p(j), pt_idx)
             end do
             
             call mesh_add_element(msh, i, p(1), p(2), p(3), p(4))
          end do
          deallocate(re2v1_data_xy)
       else
          allocate(re2v2_data_xy(nelv))
          call MPI_File_read_at_all(fh, mpi_offset, &
               re2v2_data_xy, nelv, MPI_RE2V2_DATA_XY, status, ierr)
          do i = 1, nelv
             do j = 1, 4             
                p(j) = point_t(re2v2_data_xy(i)%x(j), &
                     re2v2_data_xy(i)%y(j), 0.0d0)
                call re2_file_add_point(htp, p(j), pt_idx)
             end do
             
             call mesh_add_element(msh, i, p(1), p(2), p(3), p(4))
          end do
          deallocate(re2v2_data_xy)
       end if
    else if (ndim .eq. 3) then
       mpi_offset = mpi_offset + element_offset * re2_data_xyz_size
       if (.not. v2_format) then
          allocate(re2v1_data_xyz(nelv))
          call MPI_File_read_at_all(fh, mpi_offset, &
               re2v1_data_xyz, nelv, MPI_RE2V1_DATA_XYZ, status, ierr)
          do i = 1, nelv
             do j = 1, 8             
                p(j) = point_t(real(re2v1_data_xyz(i)%x(j),dp), &
                     real(re2v1_data_xyz(i)%y(j),dp),&
                     real(re2v1_data_xyz(i)%z(j),dp))
                call re2_file_add_point(htp, p(j), pt_idx)
             end do
             
             call mesh_add_element(msh, i, &
                  p(1), p(2), p(3), p(4), p(5), p(6), p(7), p(8))          
          end do
          deallocate(re2v1_data_xyz)
       else
          allocate(re2v2_data_xyz(nelv))
          call MPI_File_read_at_all(fh, mpi_offset, &
               re2v2_data_xyz, nelv, MPI_RE2V2_DATA_XYZ, status, ierr)
          do i = 1, nelv
             do j = 1, 8             
                p(j) = point_t(re2v2_data_xyz(i)%x(j), &
                     re2v2_data_xyz(i)%y(j),&
                     re2v2_data_xyz(i)%z(j))
                call re2_file_add_point(htp, p(j), pt_idx)
             end do
             
             call mesh_add_element(msh, i, &
                  p(1), p(2), p(3), p(4), p(5), p(6), p(7), p(8))          
          end do
          deallocate(re2v2_data_xyz)
       end if
    end if

    call htp%free()
  end subroutine re2_file_read_points

  subroutine re2_file_read_curve(msh, ncurve, dist, fh, mpi_offset, v2_format)
    type(mesh_t), intent(inout) :: msh
    integer (kind=MPI_OFFSET_KIND) :: mpi_offset
    integer, intent(inout) :: ncurve
    type(linear_dist_t) :: dist
    type(MPI_File), intent(inout) :: fh
    logical, intent(in) :: v2_format
    type(MPI_Status) :: status
    integer :: p_el_idx, p_facet
    integer :: i, j, l, ierr, pt_idx, el_idx, id
    type(re2v1_curve_t), allocatable :: re2v1_data_curve(:)
    type(re2v2_curve_t), allocatable :: re2v2_data_curve(:)    
    real(kind=dp), allocatable :: curve_data(:,:,:)
    integer, allocatable :: curve_type(:,:)
    logical, allocatable :: curve_element(:)
    character(len=4) :: chtemp
    logical :: curve_skip = .false.
 
    allocate(curve_data(5,8,msh%nelv))
    allocate(curve_element(msh%nelv))
    allocate(curve_type(8,msh%nelv))
    do i = 1, msh%nelv
       curve_element(i) = .false.
       do j = 1, 8
          curve_type(j,i) = 0
          do l = 1, 5
             curve_data(l,j,i) = 0d0
          end do
       end do
    end do
  
    if (.not. v2_format) then
       allocate(re2v1_data_curve(ncurve))
       call MPI_File_read_at_all(fh, mpi_offset, re2v1_data_curve, ncurve, &
            MPI_RE2V1_DATA_CV, status, ierr)
    else
       allocate(re2v2_data_curve(ncurve))
       call MPI_File_read_at_all(fh, mpi_offset, re2v2_data_curve, ncurve, &
            MPI_RE2V2_DATA_CV, status, ierr)
    end if
    !This can probably be made nicer...
    do i = 1, ncurve
       if(v2_format) then
          el_idx = re2v2_data_curve(i)%elem - dist%start_idx()
          id = re2v2_data_curve(i)%face
          chtemp = re2v2_data_curve(i)%type
          do j = 1, 5 
             curve_data(j,id, el_idx) = re2v2_data_curve(i)%point(j)
          enddo
       else 
          el_idx = re2v1_data_curve(i)%elem - dist%start_idx()
          id = re2v1_data_curve(i)%face
          chtemp = re2v1_data_curve(i)%type
          do j = 1, 5 
             curve_data(j,id, el_idx) = real(re2v1_data_curve(i)%point(j),dp) 
          enddo
       end if
       
       curve_element(el_idx) = .true. 
       !This might need to be extended
       select case(trim(chtemp))
       case ('s')
         curve_type(id,el_idx) = 1
         call neko_warning('curve type s not supported, treating mesh as non-curved')
         curve_skip = .true.
         exit
       case ('e')
         curve_type(id,el_idx) = 2
         call neko_warning('curve type e not supported, treating mesh as non-curved')
         curve_skip = .true.
         exit
       case ('C')
         curve_type(id,el_idx) = 3
       end select
    end do

    if( v2_format) then
       deallocate(re2v2_data_curve)
    else
       deallocate(re2v1_data_curve)
    end if
    if (.not. curve_skip) then
       do el_idx = 1, msh%nelv
          if (curve_element(el_idx)) then
             call mesh_mark_curve_element(msh, el_idx, curve_data(1,1,el_idx), curve_type(1,el_idx))
          end if
       end do 
     end if

    deallocate(curve_data)
    deallocate(curve_element)
    deallocate(curve_type)
  end subroutine re2_file_read_curve


  subroutine re2_file_read_bcs(msh, nbcs, dist, fh, mpi_offset, v2_format)
    type(mesh_t), intent(inout) :: msh
    integer (kind=MPI_OFFSET_KIND) :: mpi_offset
    integer, intent(inout) :: nbcs
    type(linear_dist_t) :: dist
    type(MPI_File), intent(inout) :: fh
    logical, intent(in) :: v2_format
    type(MPI_Status) :: status
    integer :: pids(4)
    integer :: sym_facet
    integer :: p_el_idx, p_facet
    integer :: i, j, ierr, pt_idx, el_idx
    integer, parameter, dimension(6) :: facet_map = (/3, 2, 4, 1, 5, 6/)
    logical :: periodic
    type(re2v1_bc_t), allocatable :: re2v1_data_bc(:)
    type(re2v2_bc_t), allocatable :: re2v2_data_bc(:)    

    if (.not. v2_format) then
       allocate(re2v1_data_bc(nbcs))
       call MPI_File_read_at_all(fh, mpi_offset, re2v1_data_bc, nbcs, &
            MPI_RE2V1_DATA_BC, status, ierr)
    else
       allocate(re2v2_data_bc(nbcs))
       call MPI_File_read_at_all(fh, mpi_offset, re2v2_data_bc, nbcs, &
            MPI_RE2V2_DATA_BC, status, ierr)
    end if

    periodic = .false.
    
    !> @todo Use element offset in parallel
    if (v2_format) then ! V2 format
       do i = 1, nbcs
          el_idx = re2v2_data_bc(i)%elem - dist%start_idx()
          sym_facet = facet_map(re2v2_data_bc(i)%face)
          select case(trim(re2v2_data_bc(i)%type))
          case ('W')
             call mesh_mark_wall_facet(msh, sym_facet, el_idx)
          case ('v', 'V')
             call mesh_mark_inlet_facet(msh, sym_facet, el_idx)
          case ('O', 'o')
             call mesh_mark_outlet_facet(msh, sym_facet, el_idx)
          case ('SYM')
             call mesh_mark_sympln_facet(msh, sym_facet, el_idx)
          case ('P')
             periodic = .true.
             p_el_idx = int(re2v2_data_bc(i)%bc_data(1))
             p_facet = facet_map(int(re2v2_data_bc(i)%bc_data(2)))
             call mesh_get_facet_ids(msh, sym_facet, el_idx, pids)
             call mesh_mark_periodic_facet(msh, sym_facet, el_idx, &
                  p_facet, p_el_idx, pids)
          end select
       end do
    
       !
       ! Fix periodic condition for shared nodes
       !
       if (periodic) then
          do j = 1, 3
             do i = 1, nbcs
                el_idx = re2v2_data_bc(i)%elem - dist%start_idx()
                sym_facet = facet_map(re2v2_data_bc(i)%face)
                select case(trim(re2v2_data_bc(i)%type))
                case ('P')
                   p_el_idx = int(re2v2_data_bc(i)%bc_data(1))
                   p_facet = facet_map(int(re2v2_data_bc(i)%bc_data(2)))
                   call mesh_create_periodic_ids(msh, sym_facet, el_idx, &
                        p_facet, p_el_idx) 
                end select
             end do
          end do
       end if
       deallocate(re2v2_data_bc)
          
    else ! V! format
       do i = 1, nbcs
          el_idx = re2v1_data_bc(i)%elem - dist%start_idx()
          sym_facet = facet_map(re2v1_data_bc(i)%face)
          select case(trim(re2v1_data_bc(i)%type))
          case ('W')
             call mesh_mark_wall_facet(msh, sym_facet, el_idx)
          case ('v', 'V')
             call mesh_mark_inlet_facet(msh, sym_facet, el_idx)
          case ('O', 'o')
             call mesh_mark_outlet_facet(msh, sym_facet, el_idx)
          case ('SYM')
             call mesh_mark_sympln_facet(msh, sym_facet, el_idx)
          case ('P')
             periodic = .true.
             p_el_idx = int(re2v1_data_bc(i)%bc_data(1))
             p_facet = facet_map(int(re2v1_data_bc(i)%bc_data(2)))
             call mesh_get_facet_ids(msh, sym_facet, el_idx, pids)
             call mesh_mark_periodic_facet(msh, sym_facet, el_idx, &
                  p_facet, p_el_idx, pids)
          end select
       end do
       
       !
       ! Fix periodic condition for shared nodes
       !
       if (periodic) then
          do j = 1, 3
             do i = 1, nbcs
                el_idx = re2v1_data_bc(i)%elem - dist%start_idx()
                sym_facet = facet_map(re2v1_data_bc(i)%face)
                select case(trim(re2v1_data_bc(i)%type))
                case ('P')
                   p_el_idx = int(re2v1_data_bc(i)%bc_data(1))
                   p_facet = facet_map(int(re2v1_data_bc(i)%bc_data(2)))
                   call mesh_create_periodic_ids(msh, sym_facet, el_idx, &
                        p_facet, p_el_idx) 
                end select
             end do
          end do
       end if
          
       deallocate(re2v1_data_bc)
    end if
    
  end subroutine re2_file_read_bcs


  subroutine re2_file_add_point(htp, p, idx)
    type(htable_pt_t), intent(inout) :: htp
    type(point_t), intent(inout) :: p
    integer, intent(inout) :: idx
    integer :: tmp
    
    if (htp%get(p, tmp) .gt. 0) then
       idx = idx + 1
       call htp%set(p, idx)
       call p%set_id(idx)
    else
       call p%set_id(tmp)
    end if
    
  end subroutine re2_file_add_point
  
end module re2_file