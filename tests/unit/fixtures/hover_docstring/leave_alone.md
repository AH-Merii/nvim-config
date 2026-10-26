<!-- torch 2.14.1+cpu, pydantic 2.14.1, transformers 5.20.2, polars 2.1.0; pyrefly 1.4.0 hovers, corpus torch__cat.md:12-14, pydantic__BaseModel.model_validate.md:17-18, transformers__TrainingArguments.md:8, polars__lit.md:26-31 -->
Concatenates the given sequence of tensors in `tensors` in the given dimension.  
All tensors must either have the same shape (except in the concatenating  
dimension) or be a 1-D empty tensor with size ``(0,)``.  
If validation fails, the resulting [`ValidationError`][pydantic_core.ValidationError] reports the  
rejected locations and values. [Logfire](../integrations/logfire.md) can retain the complete validation  
[`HfArgumentParser`] can turn this class into  
Expected datatypes:  
  
- `pl.lit([])` -> empty List<Null>  
- `pl.lit([1, 2, 3])` -> List<i64>  
- `pl.lit(pl.Series([]))`-> empty Series Null  
- `pl.lit(pl.Series([1, 2, 3]))` -> Series Int64  