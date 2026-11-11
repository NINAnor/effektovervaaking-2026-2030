function Image(image)
  if FORMAT:match("html") and image.attributes.loading == nil then
    image.attributes.loading = "lazy"
  end

  return image
end
