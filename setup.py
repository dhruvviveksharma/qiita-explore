from setuptools import setup, find_packages

def _is_setuptools_compatible(line):
    line = line.strip()
    if not line or line.startswith("#"):
        return False
    if line.startswith("-"):
        return False
    return True


with open("requirements.txt") as f:
    install_requires = [line.strip() for line in f if _is_setuptools_compatible(line)]

setup(
    name="qiita-explore",
    version="0.1.0",
    description="ezredbiom exploratory tooling extracted from qiita",
    packages=find_packages(),
    python_requires=">=3.9",
    install_requires=install_requires,
    classifiers=[
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "License :: OSI Approved :: BSD License",
        "Operating System :: OS Independent",
    ],
)
