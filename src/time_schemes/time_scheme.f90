! Copyright (c) 2008-2020, UCHICAGO ARGONNE, LLC. 
!
! The UChicago Argonne, LLC as Operator of Argonne National
! Laboratory holds copyright in the Software. The copyright holder
! reserves all rights except those expressly granted to licensees,
! and U.S. Government license rights.
!
! Redistribution and use in source and binary forms, with or without
! modification, are permitted provided that the following conditions
! are met:
!
! 1. Redistributions of source code must retain the above copyright
! notice, this list of conditions and the disclaimer below.
!
! 2. Redistributions in binary form must reproduce the above copyright
! notice, this list of conditions and the disclaimer (as noted below)
! in the documentation and/or other materials provided with the
! distribution.
!
! 3. Neither the name of ANL nor the names of its contributors
! may be used to endorse or promote products derived from this software
! without specific prior written permission.
!
! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
! "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
! LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
! FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
! UCHICAGO ARGONNE, LLC, THE U.S. DEPARTMENT OF 
! ENERGY OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, 
! SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
! TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
! DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY 
! THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
! (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE 
! OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
!
! Additional BSD Notice
! ---------------------
! 1. This notice is required to be provided under our contract with
! the U.S. Department of Energy (DOE). This work was produced at
! Argonne National Laboratory under Contract 
! No. DE-AC02-06CH11357 with the DOE.
!
! 2. Neither the United States Government nor UCHICAGO ARGONNE, 
! LLC nor any of their employees, makes any warranty, 
! express or implied, or assumes any liability or responsibility for the
! accuracy, completeness, or usefulness of any information, apparatus,
! product, or process disclosed, or represents that its use would not
! infringe privately-owned rights.
!
! 3. Also, reference herein to any specific commercial products, process, 
! or services by trade name, trademark, manufacturer or otherwise does 
! not necessarily constitute or imply its endorsement, recommendation, 
! or favoring by the United States Government or UCHICAGO ARGONNE LLC. 
! The views and opinions of authors expressed 
! herein do not necessarily state or reflect those of the United States 
! Government or UCHICAGO ARGONNE, LLC, and shall 
! not be used for advertising or product endorsement purposes.
!
!> Explicit and Backward Differentiation time-integration schemes
module time_scheme
  use neko_config
  use num_types, only : rp
  use utils, only : neko_warning
  use device, only : device_free, device_map
  use, intrinsic :: iso_c_binding
  implicit none
  private
  
  !> Base abstract class for time integration schemes
  !! @details
  !! An important detail here is the handling of the first timesteps where a 
  !! high-order scheme cannot be constructed. The parameters `n`, which is
  !! initialized to 0, must be incremented by 1 in the beggining of the 
  !! `set_coeffs` routine to determine the current scheme order.
  !! When `n == time_order`, the incrementation should stop.
  type, abstract, public :: time_scheme_t
     !> The coefficients of the scheme
     real(kind=rp), dimension(4) :: coeffs 
     !> Controls the actual order of the scheme, e.g. 1 at the first time-step
     integer :: n = 0
     !> Order of the scheme, defaults to 3
     integer :: time_order
     !> Device pointer for `coeffs`
     type(c_ptr) :: coeffs_d = C_NULL_PTR 
   contains
     !> Controls current scheme order and computes the coefficients
     procedure(set_coeffs), deferred, pass(this) :: set_coeffs
     !> Constructor
     procedure, pass(this) :: init => time_scheme_init 
     !> Destructor
     procedure, pass(this) :: free => time_scheme_free
  end type time_scheme_t
  
  abstract interface
     !> Interface for setting the scheme coefficients
     !! @param t Timestep values, first element is the current timestep.
     subroutine set_coeffs(this, dt)
       import time_scheme_t
       import rp
       class(time_scheme_t), intent(inout) :: this
       real(kind=rp), intent(inout), dimension(10) :: dt
     end subroutine
  end interface
  

  

contains
  !> Constructor
  !! @param torder Desired order of the scheme: 1, 2 or 3.
  subroutine time_scheme_init(this, torder)
    class(time_scheme_t), intent(inout) :: this
    integer, intent(in) :: torder

    if(torder .le. 3 .and. torder .gt. 0) then
       this%time_order = torder
    else
       this%time_order = 3
       call neko_warning('Invalid time order, defaulting to 3')
    end if

    if (NEKO_BCKND_DEVICE .eq. 1) then
       call device_map(this%coeffs, this%coeffs_d, 4)
    end if
  end subroutine time_scheme_init

  !> Destructor
  subroutine time_scheme_free(this)
    class(time_scheme_t), intent(inout) :: this

    if (c_associated(this%coeffs_d)) then
       call device_free(this%coeffs_d)
    end if
  end subroutine time_scheme_free

  
end module time_scheme
