# Copyright 1999-2018 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6

PYTHON_COMPAT=( python2_7 )

inherit eutils flag-o-matic fortran-2 python-any-r1 toolchain-funcs versionator

MY_P="${PN}-$(replace_version_separator _ -)"

DESCRIPTION="Portable, Extensible Toolkit for Scientific Computation"
HOMEPAGE="http://www.mcs.anl.gov/petsc/"
SRC_URI="http://ftp.mcs.anl.gov/pub/petsc/release-snapshots/${MY_P}.tar.gz"

LICENSE="BSD-2"
SLOT="0"
KEYWORDS="~x86 ~amd64"
IUSE="afterimage boost complex-scalars cxx debug doc fftw
	fortran hdf5 hypre mpi metis mumps scotch sparse superlu threads X"

# hypre and superlu curretly exclude each other due to missing linking to hypre
# if both are enabled
REQUIRED_USE="
	afterimage? ( X )
	complex-scalars? ( !hypre !superlu )
	hdf5? ( mpi )
	hypre? ( cxx mpi !superlu )
	mumps? ( mpi scotch )
	scotch? ( mpi )
	superlu? ( !hypre )
"

RDEPEND="
	virtual/blas
	virtual/lapack
	afterimage? ( media-libs/libafterimage )
	boost? ( dev-libs/boost )
	fftw? ( sci-libs/fftw:3.0[mpi?] )
	hdf5? ( sci-libs/hdf5[mpi?] )
	hypre? ( >=sci-libs/hypre-2.8.0b[mpi?] )
	metis? ( >=sci-libs/parmetis-4 )
	mpi? ( virtual/mpi[cxx?,fortran?] )
	mumps? ( sci-libs/mumps[mpi?] sci-libs/scalapack )
	scotch? ( sci-libs/scotch[mpi?] )
	sparse? ( sci-libs/suitesparse >=sci-libs/cholmod-1.7.0 )
	superlu? ( >=sci-libs/superlu-5 )
	X? ( x11-libs/libX11 )
"

DEPEND="${RDEPEND}
	${PYTHON_DEPS}
	virtual/pkgconfig
	dev-util/cmake
"

#
# PETSc does not want its Makefiles to be invoked with anything higher than
# -j1. The underlying build system does automatically invoke a parallel
# build. This might not be what you want, but *hey* not your choice.
#
# V=1 enables verbose output with full compiler and linker invocation
#
MAKEOPTS="${MAKEOPTS} -j1 V=1"

S="${WORKDIR}/${MY_P}"

PATCHES=(
	"${FILESDIR}"/${PN}-3.7.0-disable-rpath.patch \
	"${FILESDIR}"/${PN}-3.8.3-fix_sandbox_violation.patch
)

src_prepare() {
	default

	sed -i -e 's%/usr/bin/env python%/usr/bin/env python2%' configure || die
}

# petsc uses --with-blah=1 and --with-blah=0 to en/disable options
petsc_enable() {
	use "$1" && echo "--with-${2:-$1}=1" || echo "--with-${2:-$1}=0"
}
# add external library:
# petsc_with use_flag libname libdir
# petsc_with use_flag libname include linking_libs
petsc_with() {
	local myuse p=${2:-${1}}
	if use ${1}; then
		myuse="--with-${p}=1"
		if [[ $# -ge 4 ]]; then
			myuse="${myuse} --with-${p}-include=${EPREFIX}${3}"
			shift 3
			myuse="${myuse} --with-${p}-lib=$@"
		else
			myuse="${myuse} --with-${p}-dir=${EPREFIX}${3:-/usr}"
		fi
	else
		myuse="--with-${p}=0"
	fi
	echo ${myuse}
}

# select between configure options depending on use flag
petsc_select() {
	use "$1" && echo "--with-$2=$3" || echo "--with-$2=$4"
}

src_configure() {
	# bug 548498
	# PETSc runs mpi processes during configure that result in a sandbox
	# violation by trying to open /proc/mtrr rw. This is not easy to
	# mitigate because it happens in libpciaccess.so called by libhwloc.so,
	# which is used by libmpi.so.
	addpredict /proc/mtrr
	# if mpi is built with knem support it needs /dev/knem too
	addpredict /dev/knem

	# configureMPITypes with openmpi-2* insists on accessing the scaling
	# governor rw.
	addpredict /sys/devices/system/cpu/

	local mylang
	local myopt

	use cxx && mylang="cxx" || mylang="c"
	use debug && myopt="debug" || myopt="opt"

	# environmental variables expected by petsc during build

	export PETSC_DIR="${S}"
	export PETSC_ARCH="linux-gnu-${mylang}-${myopt}"

	if use debug; then
		strip-flags
		filter-flags -O*
	fi

	# C Support on CXX builds is enabled if possible i.e. when not using
	# complex scalars (no complex type for both available at the same time)

	econf \
		scrollOutput=1 \
		FFLAGS="${FFLAGS} -fPIC" \
		CFLAGS="${CFLAGS} -fPIC" \
		CXXFLAGS="${CXXFLAGS} -fPIC" \
		LDFLAGS="${LDFLAGS}" \
		--prefix="${EPREFIX}/usr/$(get_libdir)/petsc" \
		--with-shared-libraries \
		--with-single-library \
		--with-clanguage=${mylang} \
		$(use cxx && ! use complex-scalars && echo "with-c-support=1") \
		--with-petsc-arch=${PETSC_ARCH} \
		--with-precision=double \
		--with-gnu-compilers \
		--with-blas-lapack-lib="$($(tc-getPKG_CONFIG) --libs lapack)" \
		$(petsc_enable debug debugging) \
		$(petsc_enable mpi) \
		$(petsc_select mpi cc mpicc $(tc-getCC)) \
		$(petsc_select mpi cxx mpicxx $(tc-getCXX)) \
		$(petsc_enable fortran) \
		$(use fortran && echo "$(petsc_select mpi fc mpif77 $(tc-getF77))") \
		$(petsc_enable mpi mpi-compilers) \
		$(petsc_select complex-scalars scalar-type complex real) \
		--with-windows-graphics=0 \
		--with-matlab=0 \
		--with-cmake=cmake \
		$(petsc_enable threads pthread) \
		$(petsc_with afterimage afterimage \
			/usr/include/libAfterImage -lAfterImage) \
		$(petsc_with hdf5) \
		$(petsc_with hypre hypre \
			/usr/include/hypre -lHYPRE) \
		$(petsc_with sparse suitesparse) \
		$(petsc_with superlu superlu \
			/usr/include/superlu -lsuperlu) \
		$(petsc_with X x) \
		$(petsc_with X x11) \
		$(petsc_with scotch ptscotch \
			/usr/include/scotch \
		[-lptesmumps,-lptscotch,-lptscotcherr,-lscotch,-lscotcherr]) \
		$(petsc_with mumps scalapack \
			/usr/include/scalapack -lscalapack) \
		$(petsc_with mumps mumps \
			/usr/include \
			[-lcmumps,-ldmumps,-lsmumps,-lzmumps,-lmumps_common,-lpord]) \
		--with-imagemagick=0 \
		--with-python=0 \
		$(petsc_with boost) \
		$(petsc_with fftw)
}

src_install() {
	emake DESTDIR="${D}/usr/$(get_libdir)/petsc" install

	# add PETSC_DIR to environmental variables
	cat >> 99petsc <<- EOF
		PETSC_DIR=${EPREFIX}/usr/$(get_libdir)/petsc
	EOF
	doenvd 99petsc

	if use doc ; then
		dodoc docs/developers.pdf docs/manual.pdf
		dohtml -r docs/*.html docs/changes docs/manualpages
	fi
}