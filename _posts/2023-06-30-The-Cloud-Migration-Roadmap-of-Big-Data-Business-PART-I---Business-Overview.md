---
title: "The Cloud Migration Roadmap of Big Data Business PART I - Business Overview"
author: Xinjie (Edward) HU
date: 2023-06-30
category: [Notes]
tags: [Cloud Migration, Data Warehouse, Technical Notes]
---

# Introduction
In 2023 Q1, I participated in the cloud migration project for big data business in our department, from on-premises to [Tencent Cloud](https://www.tencentcloud.com/). After the migration, we reached the goal of **cost reduction and increasing operation & maintenance efficiency**.

Some experience and works during this process has been summarized. The whole content has been split into three techinical notes:  
**PART I (this article):** the big data business overview of my department (not confidential things included),  

**PART II:** the work and experience involved in the infrastructure, historical data, business system and other modules during cloud migration,  

**PART III:** the key technological reforms. 

# Big Data Business Overview
## Business Classification

The big data business classification standard could be set from two orthogonal dimensions: the operation and the timeliness requirement. 

### Data Operation

Within the data operation dimension, it is divided into two parts: data production and analysis application. 

> **Data production** can be understood as generalized ETL production, includes a series of data operations such as data cleaning, format conversion, and data association.

Key features:
- it is based on large-scale computation, with large data input and output volume, and long runtime;
- the data processing should be highly fault tolerant. For example, computing engines such as MapReduce and Spark can perform fault tolerance and Retry operations on the failure of a single Task. The entire Job or Application execution is not affected. 

> **Analysis applications** are based on data already produced and are oriented to upper-level operations, multidimensional analysis. For example, such as rolling up, drilling down, slicing, etc., 

Key features: 
- query <u>result</u> set is small: with a large amount of data input and a small amount of data output. 
- the query response timeliness requirements are extremely high, requiring falling in second or even sub-second level. 

### Timeliness Requirement
Under the data timeliness dimension, it is divided into offline data and real-time data. 

**Offline data:** the timeliness requirement is at the day or hour level. Offline data is always managed in the hierarchical modeling architecture. 

**Real-time data:** the timeliness is required at the minute/second level, and for some IOT scenarios, the delay is even strictly controlled at the sub-second level. 

Since the proportion of real-time data analysis in the total workload is fair, the *Information Silo Architecture* is adopted. 
> Information Silo Architecture means we establish different real-time data tasks according to different data production and analysis scenarios. 
{: .prompt-info }

At present, we also applied the *hierarchical architecture* to model real-time data. The underlying data is written to Kafka in real time, and provided to the high-level model; With the emergence of open source OLAP databases such as StarRocks that support real-time writing of high-throughput data, the raw data is written to the database as an ODS table after ETL, and based on these ODS table data, write complex Ad Hoc-like SQL query statements such as Join and aggregation to meet different analysis needs.  

### Business Scenario Matrix
Based on the above two dimensions, data-related business can be divided into four scenarios: 
![Business Scenario Matrix](/assets/img/big_data_cloud_migration/0_business_scenario_matrix.png)
1. **Offline analysis**, the traditional warehousing business type, that requires T+1 analysis scenario. The main technologies used in practice include Impala, Presto, StarRocks, etc.; 

2. **Real-time analysis**, aiming at real-time warehousing scenarios, using StarRocks and other technologies; 

3. **Offline ETL**, which applies to Batch Processing scenarios and uses HIVE, Spark, and MapReduce technologies 

4. **Real-time ETL**, aiming at Stream Processing scenarios, uses StarRocks, Flink, Spark Streaming, etc. Since StarRocks [Routine Load](https://docs.starrocks.io/docs/3.0/faq/loading/Routine_load_faq) supports data cleaning and data type conversion, therefore, Routine Load is directly used to perform real-time data ETL operations in some real-time analysis scenario. 

## Business Architecture
According to the above classification of big data services, the figure below shows the overall architecture of big data services of our department, which is divided into three levels: **data source, data computing and storage, and data application.** 
![Business Architecture](/assets/img/big_data_cloud_migration/1_business_architecture.png)

**Data source** layer includes two categories: 
- data produced by the business system, which is stored in MySQL, Oracle, MongoDB, and RDBMS;
- log data, the data that represents service system events, is collected from clients in tracking events or servers.

**Data computing and storage** is the most core level of the entire big data business architecture. The left side of the figure above is the offline data service part, which adopts a hierarchical model and is divided into STG/ODS/DWD/DWS/ADS tier. The right side is the real-time data business part, which adopts three data development methods, from left to right, silo architecture, hierarchical modeling, and post computation. 

1. Silo builds real-time data tasks for different businesses, and complex processing such as <kbd>JOIN</kbd> will be carried out inside ETL tasks. However, as it is overly complicated to process Join operation in Stream Processing, and problems such as data inaccuracy will exist, silo development is gradually decreasing; 

2. Hierarchical modeling, which adopts the idea of constructing different layers in offline business model. This could significantly reduce silo development, and apply scenarios such as real-time online business data update and real-time model recommendation; 

3. Post computation, which generates ODS table through real-time ETL. Business analysts write SQL solely based on ODS table data, and place calculation operations such as Join, windows and aggregation of data to the query runtime; 

**Data application** layer, interfacing with the internal BI system of the department. For example, Impala, Presto, and StarRocks, which meet the accelerated query requirements under different scenarios. 

## On-premises Technical Architecture
### Introduction
According to the big data *business* architecture mentioned above, the *technical* architecture deployed **on-premises** is shown in the figure below.
![On-premises Technical Architecture](/assets/img/big_data_cloud_migration/2_on_premises_technical_architecture.jpg) 

For offline data, Flume is utilized for log data synchronization, while Sqoop and MongoDB, Elasticsearch, Redis and other Sqoop plugins are used for service data synchronization. HDFS is used for data storage, Batch Processing uses HIVE and Spark based on YARN resource manager. The self-developed offline data management platform contains the following features: managing the data processing task workload (based on xxx-job DAG), data supplementary, data quality monitoring, metadata management, etc. Offline analysis is based on MPP query engines such as Impala/Presto/StarRocks. 

For real-time data, though Flume was still used for log data synchronization, Canal and other CDC products were used for business data synchronization. Kafka and StarRocks are used for data storage, Flink and Spark Streaming for real-time ETL, and StarRocks for real-time analytics. 

### Summary
The above is an overall introduction to the technical architecture of big data **on-premises**, and the overall summary of big data *on-premises* is as follows: 

1. Infrastructure: Hadoop cluster provided by Sohu, and there is a special team responsible for operation and maintenance. StarRocks is also built and operated by the team. 

2. Historical data: currently, the accumulated historical data is at the level of 10PB. 

3. Business system: including self-built Report, OLAP, Ad Hoc and other BI systems. Additionally, self-developed offline data management platform, for the offline data hierarchical modeling task management. The entire big data business cloud migration is centered around the above three parts.

### Pain Points
The on-premises big data architecture has also encountered some pain points in the years of development. For example, 
- the long scaling cycle of the data center makes it difficult to quickly supplement computing resources according to business requirements;
- resources need to be reserved at any time, even if there are not any computing tasks running;
- the complexity of cost-sharing for computing resources shared by multiple business units. 

These pain points have also been successfully solved after cloud migration. 