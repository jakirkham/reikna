import sys
major, minor, _, _, _ = sys.version_info
if not ((major == 2 and minor >= 6) or (major == 3 and minor >= 2)):
    print("Python >=2.6 or >=3.2 is required to use this module.")
    sys.exit(1)

try:
    from setuptools import setup
except ImportError:
    from distutils.core import setup

import os.path
import subprocess

def cd_to_project_root():
    project_root = os.path.split(os.path.realpath(__file__))[0]

    class CwdContext:
        def __enter__(self):
            self.old_path = os.getcwd()
            os.chdir(project_root)
            sys.path.insert(0, project_root)
        def __exit__(self, *args):
            del sys.path[0]
            os.chdir(self.old_path)

    return CwdContext()

def git_revision():
    """Get current git revision. Taken from numpy."""

    def _minimal_ext_cmd(cmd):
        # construct minimal environment
        env = {}
        for k in ['SYSTEMROOT', 'PATH']:
            v = os.environ.get(k)
            if v is not None:
                env[k] = v
        # LANGUAGE is used on win32
        env['LANGUAGE'] = 'C'
        env['LANG'] = 'C'
        env['LC_ALL'] = 'C'
        out = subprocess.Popen(cmd, stdout = subprocess.PIPE).communicate()[0]
        return out

    try:
        out = _minimal_ext_cmd(['git', 'rev-parse', 'HEAD'])
        revision = out.strip().decode('ascii')
    except OSError:
        revision = None

    return revision

def ensure_version_py():
    """
    Create contents for version.py. Idea taken from numpy.
    Returns version string to be passed to setup.py.
    """

    template = '''"""
This module contains information about the library version.

.. py:attribute:: version

    A tuple with version numbers, major components first.

.. py:attribute:: full_version

    A string fully identifying the current build.

.. py:attribute:: git_revision

    A string with Git SHA identifying the revision used to create this build.

.. py:attribute:: release

    A boolean variable, equals ``True`` if current version is a release version.

"""
# THIS FILE IS GENERATED BY SETUP.PY


version = {version}
full_version = "{full_version}"
git_revision = "{git_revision}"
release = {released}
'''

    VERSION = (0, 6, 8)
    RELEASED = True

    version_str = '%d.%d.%d' % VERSION
    full_version_str = version_str
    version_py_path = os.path.join('reikna', 'version.py')

    with cd_to_project_root():
        if os.path.exists('.git'):
            revision = git_revision()
        elif os.path.exists(version_py_path):
            # must be a source distribution, use existing version file
            globals_dict = {}
            with open(version_py_path) as f:
                exec(compile(f.read(), version_py_path, 'exec'), globals_dict)
            revision = globals_dict['git_revision']
        else:
            revision = None

    if revision is None:
        revision = "unknown"

    if not RELEASED:
        full_version_str += '+dev.' + revision[:7]

    contents = template.format(version=repr(VERSION),
        full_version=full_version_str, git_revision=revision, released=repr(RELEASED))

    with cd_to_project_root():
        with open(version_py_path, 'w') as f:
            f.write(contents)

    return version_str, full_version_str

if __name__ == '__main__':

    DOCUMENTATION = open('README.rst').read()
    _, VERSION_STR = ensure_version_py()

    # seuptool's ``install_requires`` and distutil's ``requires`` have slightly different format
    dependencies = [
        ('mako', '>= 0.8.0'),
        ('numpy', '>= 1.6.0'),
        ('funcsigs', '>= 0.3')]
    requires = list(map(lambda nr: nr[0] + '(' + nr[1] + ')', dependencies))
    install_requires = list(map(lambda nr: nr[0] + ' ' + nr[1], dependencies))

    setup(
        name='reikna',
        packages=[
            'reikna',
            'reikna/algorithms',
            'reikna/cbrng',
            'reikna/cluda',
            'reikna/core',
            'reikna/fft',
            'reikna/helpers',
            'reikna/linalg',
            ],
        provides=['reikna'],
        requires=requires,
        install_requires=install_requires,
        extras_require=dict(
            pyopencl=["pyopencl>=2013.1"],
            pycuda=["pycuda>=2013.1"],
            dev=[
                "pytest>=2.3",
                "pytest-cov",
                "scipy",
                "sphinx>=1.2",
                ]),
        package_data={
            'reikna': ['*.mako'],
            'reikna/algorithms': ['*.mako'],
            'reikna/cluda': ['*.mako'],
            'reikna/cbrng': ['*.mako'],
            'reikna/fft': ['*.mako'],
            'reikna/linalg': ['*.mako'],
            },
        version=VERSION_STR,
        author='Bogdan Opanchuk',
        author_email='bogdan@opanchuk.net',
        url='http://github.com/fjarri/reikna',
        description='GPGPU algorithms for PyCUDA and PyOpenCL',
        long_description=DOCUMENTATION,
        classifiers=[
            'Development Status :: 4 - Beta',
            'Intended Audience :: Science/Research',
            'Intended Audience :: Developers',
            'License :: OSI Approved :: MIT License',
            'Programming Language :: Python',
            'Programming Language :: Python :: 2',
            'Programming Language :: Python :: 2.6',
            'Programming Language :: Python :: 2.7',
            'Programming Language :: Python :: 3',
            'Programming Language :: Python :: 3.2',
            'Programming Language :: Python :: 3.3',
            'Programming Language :: Python :: 3.4',
            'Topic :: Software Development',
            'Topic :: Scientific/Engineering',
            'Operating System :: OS Independent'
        ]
    )
