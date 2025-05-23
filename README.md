# condor-enphase
[![Work in Progress](https://img.shields.io/badge/status-work--in--progress-orange)](#)
> ⚠️ This project is currently under active development. Expect breaking changes.

A Python application that fetches solar production and consumption data from a local Enphase Envoy device, writes time-series metrics to InfluxDB, and offers customizable graphing and dashboard options.

## Features
- Real-time polling of Enphase Envoy API for solar and consumption data
- Secure token-based authentication with local or Secret Manager storage
- InfluxDB v2 integration for time-series data storage
- Optional Grafana dashboards for data visualization
- Docker Compose support for local development and testing
- Terraform scripts for provisioning resources on Google Cloud

## Prerequisites
### Local
- Raspberry Pi 4+ as a Self Hosted Runner for local deployment 
### Google Cloud
- gcloud CLI authenticated and set to your GCP project
- Terraform v1.5+ installed
- Service account or user with permissions to create Compute Engine resources and Source Repos


