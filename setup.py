from setuptools import setup, find_packages

with open("requirements.txt") as f:
    install_requires = [
        line.strip()
        for line in f
        if line.strip() and not line.startswith("#")
    ]

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
