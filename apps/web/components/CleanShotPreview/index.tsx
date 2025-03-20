import { cn } from '@campsite/ui/src/utils'

interface Props {
  className?: string
  url: string
}

export function CleanShotPreview({ className, url }: Props) {
  return (
    <iframe
      className={cn('aspect-video w-full overflow-visible rounded-md', className)}
      src={url}
      allowFullScreen
      title='CleanShot Content'
      sandbox='allow-scripts allow-same-origin allow-popups allow-presentation'
      frameBorder='0'
      scrolling='no'
    />
  )
} 