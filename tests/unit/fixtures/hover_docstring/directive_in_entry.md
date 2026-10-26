<!-- polars 2.1.0, pyrefly 1.4.0 hover, corpus polars__DataFrame.join.md:24-25,65-89 -->
Parameters  
----------  
validate: {'m:m', 'm:1', '1:m', '1:1'}  
&nbsp;&nbsp;&nbsp;&nbsp;Checks if join is of specified type.  
  
&nbsp;&nbsp;&nbsp;&nbsp;.. list-table :  
```  
:header-rows: 0  
  
* - **m:m**  
  - *(Default)* Many-to-many (default). Does not result in checks.  
* - **1:1**  
  - One-to-one. Checks if join keys are unique in both left and  
    right datasets.  
* - **1:m**  
  - One-to-many. Checks if join keys are unique in left dataset.  
* - **m:1**  
  - Many-to-one. Check if join keys are unique in right dataset.  
  
```  
&nbsp;&nbsp;&nbsp;&nbsp;.. note:  
```  
This is currently not supported by the streaming engine.  
  
```  
nulls_equal  
&nbsp;&nbsp;&nbsp;&nbsp;Join on null values. By default null values will never produce matches.  