! ================================================================================================ !
! Beam Distribution EXchange
! At one or more elements, exchange the current beam distribution
! for one given by an external program.
! K. Sjobak BE/ABP-HSS, 2016
! Based on FLUKA coupling version by
! A.Mereghetti and D.Sinuela Pastor, for the FLUKA Team, 2014.
! ================================================================================================ !
module bdex

  use floatPrecision
  use crcoall
  use numerical_constants
  use parpro

  use mod_alloc
  use string_tools

  implicit none

  ! Is BDEX in use?
  logical, save :: bdex_enable
  ! Debug mode?
  logical, save :: bdex_debug

  ! BDEX in use for this element?
  ! 0: No.
  ! 1: Do a particle exchange at this element.
  ! Other values are reserved for future use.
  integer, allocatable, save :: bdex_elementAction(:) !(nele)
  ! Which BDEX channel does this element use?
  ! This points in the bdex_channel arrays.
  integer, allocatable, save :: bdex_elementChannel(:) !(nele)

  integer, parameter :: bdex_maxchannels = 16
  integer, save :: bdex_nchannels

  ! Basic data for the bdex_channels, one row/channel
  ! Column 1: Type of channel. Values:
  !           0: Channel not in use
  !           1: PIPE channel
  !           2: TCPIP channel (not implemented)
  ! Column 2: Meaning varies, based on the value of col. 1:
  !           If col 1 is PIPE, then it is the output format.
  ! Column 3: Meaning varies, based on the value of col. 1:
  !           If col 1 is PIPE, it points to the first (of two) files in bdex_stringStorage.
  ! Column 4: Meaning varies, based on the value of col. 1:
  !           If col 1 is PIPE, then it is the unit number to use (first of two consecutive).
  integer, save :: bdex_channels(bdex_maxchannels,4)
  ! The names of the BDEX channel
  character(len=getfields_l_max_string ), save :: bdex_channelNames(bdex_maxchannels)

  !Number of places in the bdex_xxStorage arrays
  integer, parameter :: bdex_maxStore=20
  integer, save :: bdex_nstringStorage
  character(len=getfields_l_max_string ), save :: bdex_stringStorage ( bdex_maxStore )

contains

  subroutine bdex_allocate_arrays
    use crcoall
    implicit none
    integer stat

    call alloc(bdex_elementAction,nele,0,'bdex_elementAction')
    call alloc(bdex_elementChannel,nele,0,'bdex_elementChannel')

  end subroutine bdex_allocate_arrays

  subroutine bdex_expand_arrays(nele_new)
    use crcoall
    implicit none
    integer, intent(in) :: nele_new

    call resize(bdex_elementAction,nele_new,0,'bdex_elementAction')
    call resize(bdex_elementChannel,nele_new,0,'bdex_elementChannel')
  end subroutine bdex_expand_arrays

  subroutine bdex_closeFiles
    implicit none

    integer i

    if (bdex_enable) then
       do i=0,bdex_nchannels
          if (bdex_channels(i,1).eq.1) then
             close(bdex_channels(i,4))   !inPipe
             write(bdex_channels(i,4)+1,"(a)") "CLOSEUNITS"
             close(bdex_channels(i,4)+1) !outPipe
          endif
       enddo
    endif
  end subroutine bdex_closeFiles

  subroutine bdex_parseElem(ch)

    use mod_common
    implicit none

    character(len=*) ch
    character getfields_fields(getfields_n_max_fields)*(getfields_l_max_string) ! Array of fields
    integer   getfields_nfields                                                 ! Number of identified fields
    integer   getfields_lfields(getfields_n_max_fields)                         ! Length of each what:
    logical   getfields_lerr                                                    ! An error flag


    integer ii,jj

    call getfields_split( ch, getfields_fields, getfields_lfields, &
         getfields_nfields, getfields_lerr )
    if ( getfields_lerr ) call prror(-1)
    if (bdex_debug) then
       write (lout,'(1x,A,I4,A)') "BDEXDEBUG> Got a ELEM block, len=", &
            len(ch), ": '"// trim(ch)// "'"
       do ii=1,getfields_nfields
          write (lout,*) "BDEXDEBUG> Field(",ii,") ='", &
               getfields_fields(ii)(1:getfields_lfields(ii)),"'"
       enddo
    endif

    !Parse ELEM
    if ( getfields_nfields .ne. 4 ) then
       write(lout,*)"ELEM expects the following arguments:"
       write(lout,*)"ELEM chanName elemName action"
       call prror(-1)
    endif

    jj = -1
    do ii=1,il !match the single element
       if ( bez(ii) .eq. getfields_fields(3)(1:getfields_lfields(3)) ) then
          jj=ii
          exit !breaks the loop
       endif
    enddo
    if (jj.eq.-1) then
       write(lout,*) "BDEX> ERROR: The element '"// &
            getfields_fields(3)(1:getfields_lfields(3)) //"' was not found "// &
            "in the single element list."
       call prror(-1)
    endif

    if (kz(jj).ne.0 .or. el(jj).gt.pieni) then
       write(lout,*) "BDEX> Error: The element ",bez(jj), &
            "is not a marker. kz=", kz(jj), "el=",el(jj)
       call prror(-1)
    endif

    ! Action
    read(getfields_fields(4)(1:getfields_lfields(4)),*) bdex_elementAction(jj)
    if (bdex_elementAction(jj).ne.1) then
       write(lout,*) "BDEX> Error: Only action 1 (exchange) is currently supported."
       call prror(-1)
    endif

    bdex_elementChannel(jj) = -1
    do ii=1,bdex_nchannels !Match channel name
       if ( bdex_channelNames(ii)(1:getfields_lfields(2)) .eq. &
            getfields_fields(2)(1:getfields_lfields(2)) ) then
          bdex_elementChannel(jj)=ii
       endif
    enddo
    if ( bdex_elementChannel(jj).eq.-1 ) then
       write(lout,*) "BDEX> ERROR: The channel '"// &
            getfields_fields(2)(1:getfields_lfields(2)) //"' was not found"
       call prror(-1)
    endif

  end subroutine bdex_parseElem

  subroutine bdex_parseChan(ch)

    use mod_common
    use string_tools

    implicit none

    character(len=*) ch
    character getfields_fields(getfields_n_max_fields)*(getfields_l_max_string) ! Array of fields
    integer   getfields_nfields                                                 ! Number of identified fields
    integer   getfields_lfields(getfields_n_max_fields)                         ! Length of each what:
    logical   getfields_lerr                                                    ! An error flag

    integer ii,jj

    call getfields_split( ch, getfields_fields, getfields_lfields, &
         getfields_nfields, getfields_lerr )
    if ( getfields_lerr ) call prror(-1)
    if (bdex_debug) then
       write (lout,'(1x,A,I4,A)') "BDEXDEBUG> Got a CHAN block, len=", &
            len(ch), ": '"// trim(ch)// "'"
       do ii=1,getfields_nfields
          write (lout,*) &
               "BDEXDEBUG> Field(",ii,") ='", &
               getfields_fields(ii)(1:getfields_lfields(ii)),"'"
       enddo
    endif

    if ( getfields_nfields .lt. 3 ) then
       write(lout,*) "CHAN expects at least 3 arguments!"
       call prror(-1)
    endif

    !Parse CHAN
    select case( trim(stringzerotrim( getfields_fields(3) )) )
    case ("PIPE")
       call bdex_initializePipe &
            (getfields_fields,getfields_lfields,getfields_nfields)
    case ("TCPIP")
       call bdex_initializeTCPIP &
            (getfields_fields,getfields_lfields,getfields_nfields)

    case default
       !Unknown
       write(lout,*) "Error in BDEX CHAN block parsing:"
       write(lout,*) "Unknown keyword '"//trim(stringzerotrim(getfields_fields(3)))//"'"
       write(lout,*) "Expected PIPE or TCPIP"

       call prror(-1)

    end select

  end subroutine bdex_parseChan

  subroutine bdex_parseInputDone

    use mod_common
    use string_tools

    implicit none

    integer ii

    if (bdex_debug) then
       write (lout,*) "BDEXDEBUG> Finished parsing BDEX block"
    endif
    if (bdex_enable) then
       write (lout,*)
       write (lout,*) "******************************************"
       write (lout,*) "** More than one BDEX block encountered **"
       write (lout,*) "******************************************"
       call prror(-1)
    else
       bdex_enable = .true.
    endif

    if (bdex_debug) then
       write(lout,*) "BDEXDEBUG> Done parsing block, data dump:"
       write(lout,*) "BDEXDEBUG> bdex_enable = ", bdex_enable
       write(lout,*) "BDEXDEBUG> bdex_debug  = ", bdex_debug
       do ii=1,il
          if ( bdex_elementAction(ii).ne.0 ) then
             write(lout,*) "BDEXDEBUG> Single element number", ii, &
                  "named ",bez(ii), "bdex_elementAction(#)=",bdex_elementAction(ii), &
                  "bdex_elementChannel(#)=",bdex_elementChannel(ii)
          endif
       enddo
       write(lout,*) "BDEXDEBUG> bdex_nchannels=",bdex_nchannels,">=",bdex_maxchannels
       do ii=1,bdex_nchannels
          write(lout,*) "BDEXDEBUG> Channel #",ii, &
               "bdex_channelNames(#)='"// &
               trim(stringzerotrim(bdex_channelNames(ii)))//"'", &
               "bdex_channels(#,:)=",bdex_channels(ii,1),bdex_channels(ii,2), &
               bdex_channels(ii,3),bdex_channels(ii,4)
       enddo
       write(lout,*) "BDEXDEBUG> bdex_nstringStorage=", &
            bdex_nstringStorage,">=",bdex_maxStore
       do ii=1,bdex_nstringStorage
          write(lout,*) "BDEXDEBUG> #",ii,"= '"// &
               trim(stringzerotrim(bdex_stringStorage(ii)))//"'"
       enddo
       write(lout,*) "BDEXDEBUG> Dump completed."
    endif

  end subroutine bdex_parseInputDone

  subroutine bdex_comnul
    implicit none

    integer i,j

    bdex_enable=.false.
    bdex_debug =.false.
    do i=1, nele
       bdex_elementAction(i) = 0
       bdex_elementChannel(i) = 0
    end do
    bdex_nchannels=0
    do i=1, bdex_maxchannels
       bdex_channels(i,1) = 0
       bdex_channels(i,2) = 0
       bdex_channels(i,3) = 0
       bdex_channels(i,4) = 0
       do j=1,getfields_l_max_string
          bdex_channelNames(i)(j:j)=char(0)
       end do
    enddo
    bdex_nstringStorage = 0
    do i=1,bdex_maxStore
       do j=1,getfields_l_max_string
          bdex_stringStorage(i)(j:j)=char(0)
       end do
    end do

  end subroutine bdex_comnul

  ! The following subroutines where extracted from deck bdexancil:
  ! Deck with the initialization etc. routines for BDEX

  subroutine bdex_initializePipe( getfields_fields, getfields_lfields,getfields_nfields )

    use parpro
    use string_tools

    implicit none

    character, intent(in) :: getfields_fields(getfields_n_max_fields)*(getfields_l_max_string)
    integer,   intent(in) :: getfields_nfields
    integer,   intent(in) :: getfields_lfields(getfields_n_max_fields)

    !Temp variables
    ! For checking files before opening:
    logical lopen
    integer stat

    !PIPE: Use a pair of pipes to communicate the particle distributions
    !Arguments: InFileName OutFileName format fileUnit
    if ( getfields_nfields .ne. 7 ) then
       write(lout,*) "CHAN PIPE expects the following arguments:"
       write(lout,*) "CHAN chanName PIPE InFileName OutFileName format fileUnit"
       call prror(-1)
    endif

    bdex_nchannels = bdex_nchannels+1
    if (bdex_nchannels.gt.bdex_maxchannels) then
       write(lout,*) "BDEX: max channels exceeded!"
       call prror(-1)
    endif

    if (bdex_nStringStorage+2.gt.bdex_maxStore) then
       write(lout,*) "BDEX: maxStore exceeded for strings!"
       call prror(-1)
    endif

    !Store config data

    ! channelName
    bdex_channelNames(bdex_nchannels)(1:getfields_lfields(2)) = &
         getfields_fields(2)(1:getfields_lfields(2))

    ! TYPE is PIPE
    bdex_channels(bdex_nchannels,1) = 1

    bdex_nstringStorage = bdex_nstringStorage+1
    bdex_channels(bdex_nchannels,3) = bdex_nstringStorage

    ! inPipe
    bdex_stringStorage(bdex_nstringStorage)(1:getfields_lfields(4)) = &
         getfields_fields(4)(1:getfields_lfields(4))

    ! outPipe
    bdex_nstringStorage = bdex_nstringStorage+1
    bdex_stringStorage(bdex_nstringStorage)(1:getfields_lfields(5)) = &
         getfields_fields(5)(1:getfields_lfields(5))

    ! Output Format
    read(getfields_fields(6)(1:getfields_lfields(6)),*) &
         bdex_channels(bdex_nchannels,2)

    ! fileUnit
    read(getfields_fields(7)(1:getfields_lfields(7)),*) &
         bdex_channels(bdex_nchannels,4)

    ! Open the inPipe
    inquire( unit=bdex_channels(bdex_nchannels,4),opened=lopen )
    if (lopen) then
       write(lout,*)"BDEX> ERROR in daten():BDEX:CHAN:PIPE"
       write(lout,*)"BDEX> unit=",bdex_channels(bdex_nchannels,4), &
            "for file '"//bdex_stringStorage(bdex_channels(bdex_nchannels,3) ) &
            //"' was already taken"
       call prror(-1)
    end if

    write(lout,*) "BDEX> Opening input pipe '"// &
         trim(stringzerotrim(bdex_stringStorage(bdex_channels(bdex_nchannels,3)) ))//"'"
    open(unit=bdex_channels(bdex_nchannels,4), &
         file=bdex_stringStorage( bdex_channels(bdex_nchannels,3) ), &
         action='read',iostat=stat,status="OLD")
    if (stat .ne. 0) then
       write(lout,*) "BDEX> Error opening file '", &
            bdex_stringStorage( bdex_channels(bdex_nchannels,3) ), "', stat=",stat
       call prror(-1)
    endif

    ! Open the outPipe
    inquire(unit=bdex_channels(bdex_nchannels,4)+1,opened=lopen)
    if (lopen) then
       write(lout,*)"BDEX> ERROR in daten():PIPE "
       write(lout,*)"BDEX> unit=",bdex_channels(bdex_nchannels,4)+1, &
            "for file '"//bdex_stringStorage(bdex_channels(bdex_nchannels,3)+1 ) &
            //"' was already taken"
       call prror(-1)
    end if

    write(lout,*) "BDEX> Opening output pipe '"// &
         trim(stringzerotrim(bdex_stringStorage(bdex_channels(bdex_nchannels,3)+1) ))//"'"
    open(unit=bdex_channels(bdex_nchannels,4)+1, &
         file=bdex_stringStorage( bdex_channels(bdex_nchannels,3)+1 ), &
         action='write',iostat=stat,status="OLD")
    if (stat .ne. 0) then
       write(lout,*) "BDEX> Error opening file '", &
            bdex_stringStorage( bdex_channels(bdex_nchannels,3)+1 ),"' stat=", stat
       call prror(-1)
    endif
    write(bdex_channels(bdex_nchannels,4)+1,'(a)') "BDEX-PIPE !******************!"

  end subroutine bdex_initializePipe

  subroutine bdex_initializeTCPIP( getfields_fields,getfields_lfields,getfields_nfields )

    use parpro
    use string_tools

    implicit none

    character, intent(in) :: getfields_fields(getfields_n_max_fields)*(getfields_l_max_string)
    integer,   intent(in) :: getfields_nfields
    integer,   intent(in) :: getfields_lfields(getfields_n_max_fields)

    !TCPIP: Communicate over a TCP/IP port, like the old FLUKA coupling version did.
    ! Currently not implemented.
    write(lout,*) "CHAN TCPIP currently not supported in BDEX."
    call prror(-1)

  end subroutine bdex_initializeTCPIP

  ! The following subroutines where extracted from deck bdexancil:
  ! Deck with the routines used by BDEX during tracking

  subroutine bdex_track(i,ix,n)

    use parpro
    use string_tools
    use mod_common
    use mod_commont
    use mod_commonmn

    implicit none
    ! i  : current structure element
    ! ix : current single element
    ! n  : turn number

    integer i, ix,n
    intent(in) i, ix, n

#ifdef CRLIBM
    !Needed for string conversions for BDEX
    character(len=8192) ch
    integer dtostr
#endif
    !Temp variables
    integer j, k, ii

    if (bdex_elementAction(ix).eq.1) then !Particle exchange
       if (bdex_debug) then
          write(lout,*) "BDEXDEBUG> "// "Doing particle exchange in bez=",bez(ix)
       endif

       if (bdex_channels(bdex_elementChannel(ix),1).eq.1) then !PIPE channel
          !TODO: Fix the format!
          write(bdex_channels(bdex_elementChannel(ix),4)+1, &
               '(a,i10,1x,a,a,1x,a,i10,1x,a,i5)') &
               "BDEX TURN=",n,"BEZ=",bez(ix),"I=",i,"NAPX=",napx

          !Write out particles
#ifdef CRLIBM
          do j=1,napx
             do k=1,8192
                ch(k:k)=' '
             enddo
             ii=1
             ii=dtostr(xv(1,j),ch(ii:ii+24))+1+ii
             ii=dtostr(yv(1,j),ch(ii:ii+24))+1+ii
             ii=dtostr(xv(2,j),ch(ii:ii+24))+1+ii
             ii=dtostr(yv(2,j),ch(ii:ii+24))+1+ii
             ii=dtostr(sigmv(j),ch(ii:ii+24))+1+ii
             ii=dtostr(ejv(j),ch(ii:ii+24))+1+ii
             ii=dtostr(ejfv(j),ch(ii:ii+24))+1+ii
             ii=dtostr(rvv(j),ch(ii:ii+24))+1+ii
             ii=dtostr(dpsv(j),ch(ii:ii+24))+1+ii
             ii=dtostr(oidpsv(j),ch(ii:ii+24))+1+ii
             ii=dtostr(dpsv1(j),ch(ii:ii+24))+1+ii

             if (ii .ne. 1+(24+1)*11) then !Also check if too big?
                write(lout,*) "BDEX> ERROR, ii=",ii
                write(lout,*) "ch=",ch
                call prror(-1)
             endif

             write(ch(ii:ii+24),'(i24)') nlostp(j)

             write(bdex_channels(bdex_elementChannel(ix),4)+1,'(a)') ch(1:ii+24)

          enddo
#else
          do j=1,napx
             write(bdex_channels(bdex_elementChannel(ix),4)+1,*) &
                  xv(1,j),yv(1,j),xv(2,j),yv(2,j),sigmv(j), &
                  ejv(j),ejfv(j),rvv(j),dpsv(j),oidpsv(j), &
                  dpsv1(j),nlostp(j)
          enddo
#endif
          write(bdex_channels(bdex_elementChannel(ix),4)+1,'(a)') "BDEX WAITING..."

          !Read back particles
          read(bdex_channels(bdex_elementChannel(ix),4),*) j

          if ( j .eq. -1 ) then
             !Don't change the distribution at all
             if (bdex_debug) then
                write(lout,*) "BDEXDEBUG> No change in distribution."
             endif
          else
             if (j.gt.npart) then
                write(lout,*) "BDEX> ERROR: j=",j,">",npart
                call prror(-1)
 !               No longer error, but expand the npart array instead
!                 call expand_arrays(nele, j, nblz, nblo)
             endif
             napx=j
             if (bdex_debug) then
                write(lout,*) "BDEXDEBUG> Reading",napx, "particles back..."
             endif
             do j=1,napx
                read(bdex_channels(bdex_elementChannel(ix),4),*) &
                     xv(1,j),yv(1,j),xv(2,j),yv(2,j),sigmv(j), &
                     ejv(j),ejfv(j),rvv(j),dpsv(j),oidpsv(j), &
                     dpsv1(j),nlostp(j)
             enddo
          endif

          write(bdex_channels(bdex_elementChannel(ix),4)+1,'(a)') "BDEX TRACKING..."
       endif

    else
       write(lout,*) "BDEX> elementAction=", bdex_elementAction(i), "not understood."
       call prror(-1)
    endif

  end subroutine bdex_track

end module bdex