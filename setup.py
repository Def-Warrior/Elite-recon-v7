#!/usr/bin/env python3
"""
Elite Recon v7.0 — Python helper module setup
Installs the Python utilities used by elite_recon_v7.sh
"""

from setuptools import setup, find_packages
import os

here = os.path.abspath(os.path.dirname(__file__))

# Read requirements
with open(os.path.join(here, 'requirements.txt'), encoding='utf-8') as f:
    requirements = [
        line.strip() for line in f
        if line.strip() and not line.startswith('#')
    ]

# Read README
with open(os.path.join(here, 'README.md'), encoding='utf-8') as f:
    long_description = f.read()

setup(
    name='elite-recon',
    version='7.0.0',
    description='OWASP 2025 Bug Bounty Reconnaissance & Vulnerability Framework',
    long_description=long_description,
    long_description_content_type='text/markdown',
    author='Elite Recon Contributors',
    license='MIT',
    python_requires='>=3.8',
    install_requires=requirements,
    packages=find_packages(exclude=['tests*', 'docs*']),
    entry_points={
        'console_scripts': [
            # Future Python CLI wrapper
            # 'elite-recon=elite_recon.cli:main',
        ],
    },
    classifiers=[
        'Development Status :: 5 - Production/Stable',
        'Intended Audience :: Information Technology',
        'Intended Audience :: Science/Research',
        'Topic :: Security',
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10',
        'Programming Language :: Python :: 3.11',
        'Programming Language :: Python :: 3.12',
        'Operating System :: POSIX :: Linux',
    ],
    keywords=[
        'security', 'bug-bounty', 'penetration-testing',
        'recon', 'vulnerability-scanner', 'owasp', 'authorized-testing'
    ],
    project_urls={
        'Bug Reports': 'https://github.com/YOUR_USERNAME/elite-recon/issues',
        'Source':      'https://github.com/YOUR_USERNAME/elite-recon',
    },
)
