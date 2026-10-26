<!-- polars 2.1.0, pyrefly 1.4.0 hover, corpus polars__DataFrame.filter.md:39-63 -->
```python  
>>> df = pl.DataFrame(  
...     {  
...         "foo": [1, 2, 3, None, 4, None, 0],  
...         "bar": [6, 7, 8, None, None, 9, 0],  
...         "ham": ["a", "b", "c", None, "d", "e", "f"],  
...     }  
... )  
  
```  
Filter rows matching a condition:  
  
```python  
>>> df.filter(pl.col("foo") > 1)  
```  
shape: (3, 3)  
┌─────┬──────┬─────┐  
│ foo ┆ bar  ┆ ham │  
│ --- ┆ ---  ┆ --- │  
│ i64 ┆ i64  ┆ str │  
╞═════╪══════╪═════╡  
│ 2   ┆ 7    ┆ b   │  
│ 3   ┆ 8    ┆ c   │  
│ 4   ┆ null ┆ d   │  
└─────┴──────┴─────┘  