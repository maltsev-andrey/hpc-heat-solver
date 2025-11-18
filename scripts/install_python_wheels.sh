#!/bin/bash
# install_python_wheels.sh
# Install Python packages from downloaded wheels on offline nodes
# First upgrades pip, then installs packages

PACKAGE_DIR="/nfs/shared/python_local_packages"

echo "=========================================="
echo "Installing Python packages on $(hostname)"
echo "=========================================="

# Step 1: Download pip wheel on head node if not present
if [ "$(hostname)" == "srv-hpc-01" ] && [ ! -f "${PACKAGE_DIR}/pip-24.3.1-py3-none-any.whl" ]; then
    echo "Downloading pip wheel on head node..."
    cd ${PACKAGE_DIR}
    curl -O https://files.pythonhosted.org/packages/f4/b1/b422acd212ad7eedddaf7981eee6e5de085154ff726459cf2da7c5a184c1/pip-24.3.1-py3-none-any.whl
    echo "Pip wheel downloaded"
fi

# Step 2: Check current pip version
echo "Current pip version:"
pip3 --version

# Step 3: Upgrade pip from local wheel (if available)
if [ -f "${PACKAGE_DIR}/pip-24.3.1-py3-none-any.whl" ]; then
    echo "Upgrading pip from local wheel..."
    python3 -m pip install --user ${PACKAGE_DIR}/pip-24.3.1-py3-none-any.whl
elif [ -f "${PACKAGE_DIR}/pip-25.3-py3-none-any.whl" ]; then
    echo "Upgrading pip from local wheel..."
    python3 -m pip install --user ${PACKAGE_DIR}/pip-25.3-py3-none-any.whl
else
    echo "Warning: No pip wheel found, using existing pip version"
fi

# Add user's local bin to PATH for new pip
export PATH=$HOME/.local/bin:$PATH

# Show new pip version
echo "Updated pip version:"
pip3 --version

# Step 4: Determine if we need --break-system-packages flag
PIP_VERSION=$(pip3 --version | awk '{print $2}' | cut -d. -f1)
if [ "$PIP_VERSION" -ge "23" ]; then
    BREAK_FLAG="--break-system-packages"
    echo "Using --break-system-packages flag for pip >= 23"
else
    BREAK_FLAG=""
    echo "Older pip version, not using --break-system-packages"
fi

# Step 5: Install NumPy
echo ""
echo "Installing NumPy..."
pip3 install --user ${PACKAGE_DIR}/numpy-2.0.2-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl ${BREAK_FLAG}

# Step 6: Install SciPy
echo "Installing SciPy..."
pip3 install --user ${PACKAGE_DIR}/scipy-1.13.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl ${BREAK_FLAG}

# Step 7: Install mpi4py
echo "Installing mpi4py..."
export PATH=/usr/lib64/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:$LD_LIBRARY_PATH
pip3 install --user ${PACKAGE_DIR}/mpi4py-4.1.1-cp39-cp39-manylinux1_x86_64.manylinux_2_5_x86_64.whl ${BREAK_FLAG}

# Step 8: Install matplotlib and dependencies (optional)
echo ""
echo "Installing matplotlib dependencies..."
# Install in dependency order
pip3 install --user ${PACKAGE_DIR}/six-1.17.0-py2.py3-none-any.whl ${BREAK_FLAG}
pip3 install --user ${PACKAGE_DIR}/pyparsing-3.2.5-py3-none-any.whl ${BREAK_FLAG}
pip3 install --user ${PACKAGE_DIR}/packaging-25.0-py3-none-any.whl ${BREAK_FLAG}
pip3 install --user ${PACKAGE_DIR}/python_dateutil-2.9.0.post0-py2.py3-none-any.whl ${BREAK_FLAG}
pip3 install --user ${PACKAGE_DIR}/cycler-0.12.1-py3-none-any.whl ${BREAK_FLAG}
pip3 install --user ${PACKAGE_DIR}/zipp-3.23.0-py3-none-any.whl ${BREAK_FLAG}
pip3 install --user ${PACKAGE_DIR}/importlib_resources-6.5.2-py3-none-any.whl ${BREAK_FLAG}
pip3 install --user ${PACKAGE_DIR}/pillow-11.3.0-cp39-cp39-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl ${BREAK_FLAG}
pip3 install --user ${PACKAGE_DIR}/kiwisolver-1.4.7-cp39-cp39-manylinux_2_12_x86_64.manylinux2010_x86_64.whl ${BREAK_FLAG}
pip3 install --user ${PACKAGE_DIR}/fonttools-4.60.1-cp39-cp39-manylinux2014_x86_64.manylinux_2_17_x86_64.whl ${BREAK_FLAG}
pip3 install --user ${PACKAGE_DIR}/contourpy-1.3.0-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl ${BREAK_FLAG}

echo "Installing matplotlib..."
pip3 install --user ${PACKAGE_DIR}/matplotlib-3.9.4-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl ${BREAK_FLAG}

# Step 9: Test installation
echo ""
echo "=========================================="
echo "Testing installation..."
echo "=========================================="

# Test with proper Python path
export PYTHONPATH=$HOME/.local/lib/python3.9/site-packages:$PYTHONPATH

python3 -c "import numpy; print(f'✓ NumPy {numpy.__version__}')" 2>/dev/null || echo "✗ NumPy failed"
python3 -c "import scipy; print(f'✓ SciPy {scipy.__version__}')" 2>/dev/null || echo "✗ SciPy failed"
python3 -c "from mpi4py import MPI; print(f'✓ mpi4py version {MPI.Get_version()}')" 2>/dev/null || echo "✗ mpi4py failed"
python3 -c "import matplotlib; print(f'✓ Matplotlib {matplotlib.__version__}')" 2>/dev/null || echo "✗ Matplotlib failed"

echo ""
echo "Installation complete on $(hostname)!"
echo ""
echo "Packages installed to: $HOME/.local/lib/python3.9/site-packages/"
echo "Updated pip installed to: $HOME/.local/bin/"
echo ""
echo "Add to your ~/.bashrc for permanent setup:"
echo "  export PATH=\$HOME/.local/bin:\$PATH"
echo "  export PYTHONPATH=\$HOME/.local/lib/python3.9/site-packages:\$PYTHONPATH"
